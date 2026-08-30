import Foundation
import SwiftUI
import WidgetKit
import MikroTikKit

/// A one-off connection test the operator started from an interface card.
enum ConnectionTestState: Equatable {
    case running
    case finished(PingOutcome)
}

/// Owns the poll loop and everything the UI renders.
@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var snapshot: DashboardSnapshot
    @Published private(set) var history: [String: TrafficHistory] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var isRunning = false
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var connectionTests: [String: ConnectionTestState] = [:]
    /// Interfaces with an enable/disable write still in flight.
    @Published private(set) var pendingToggles: Set<String> = []

    /// Public by default, per the operator's request; persisted across launches.
    @Published var addressMode: AddressMode = AddressModeStore.load() {
        didSet { AddressModeStore.save(addressMode) }
    }

    @Published var config: RouterConfig
    @Published var credentials: RouterCredentials

    private var client: RouterClient
    private var pollTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var pingTestTasks: [String: Task<Void, Never>] = [:]
    private var toggleTasks: [String: Task<Void, Never>] = [:]
    /// RouterOS item ids from the last poll, keyed by interface name. Writing
    /// through the live `.id` keeps working if an interface is ever renamed.
    private var interfaceIDs: [String: String] = [:]
    /// Upstream gateway per interface, refreshed from the routing table.
    private var gatewaysByInterface: [String: String] = [:]
    /// Public address per WAN, refreshed on its own slow timer.
    private var publicAddresses: [String: String] = [:]
    private var publicIPTask: Task<Void, Never>?
    private var lastPublicIPAt = Date.distantPast
    private var rateTracker = RateTracker()
    private var pingResults: [String: PingOutcome] = [:]
    private var lastPingAt = Date.distantPast
    private var lastSnapshotWriteAt = Date.distantPast
    private var lastWidgetReloadAt = Date.distantPast

    /// Snapshot writes are cheap but pointless at the full poll rate.
    private let snapshotWriteInterval: TimeInterval = 5
    /// WidgetKit coalesces reloads anyway; asking more often is wasted work.
    private let widgetReloadInterval: TimeInterval = 120

    init(
        config: RouterConfig = RouterConfigStore.load(),
        credentials: RouterCredentials = CredentialStore.load()
    ) {
        self.config = config
        self.credentials = credentials
        self.client = RouterClient(config: config, credentials: credentials)
        self.snapshot = SharedStore.readSnapshot()
            ?? DashboardSnapshot(capturedAt: Date(), routerHost: config.host, isReachable: false)
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        isRunning = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = self.config.pollInterval
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 0.5) * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        pingTask?.cancel()
        pingTask = nil
        publicIPTask?.cancel()
        publicIPTask = nil
        for task in pingTestTasks.values { task.cancel() }
        pingTestTasks.removeAll()
        for task in toggleTasks.values { task.cancel() }
        toggleTasks.removeAll()
        pendingToggles.removeAll()
        isRunning = false
    }

    /// Rebuilds the client and clears derived state after a settings change.
    func applySettings(config newConfig: RouterConfig, credentials newCredentials: RouterCredentials) {
        stop()
        config = newConfig
        credentials = newCredentials
        RouterConfigStore.save(newConfig)
        try? CredentialStore.save(newCredentials)

        client = RouterClient(config: newConfig, credentials: newCredentials)
        rateTracker.reset()
        pingResults.removeAll()
        connectionTests.removeAll()
        interfaceIDs.removeAll()
        gatewaysByInterface.removeAll()
        publicAddresses.removeAll()
        lastPublicIPAt = .distantPast
        history.removeAll()
        lastPingAt = .distantPast
        lastError = nil
        start()
    }

    // MARK: - Polling

    /// True until the operator has supplied a router password.
    var needsCredentials: Bool { credentials.password.isEmpty }

    func refresh() async {
        // A first launch has no password yet. Say so plainly instead of
        // letting every poll come back as a 401.
        guard !needsCredentials else {
            lastError = "Set your router address and login in Settings (⌘,)"
            if snapshot.interfaces.isEmpty {
                snapshot = .offline(host: config.host, message: lastError!)
            }
            return
        }

        do {
            let state = try await client.fetchState()
            let now = Date()

            interfaceIDs = Dictionary(
                state.interfaces.map { ($0.name, $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
            gatewaysByInterface = Self.gateways(from: state.routes)

            var rates: [String: TrafficRate] = [:]
            for interface in state.interfaces {
                let sample = CounterSample(
                    rxBytes: interface.rxBytes,
                    txBytes: interface.txBytes,
                    timestamp: now
                )
                rates[interface.name] = rateTracker.update(interfaceName: interface.name, sample: sample)
            }

            let built = SnapshotBuilder.build(
                config: config,
                state: state,
                rates: rates,
                pings: pingResults,
                publicAddresses: publicAddresses,
                capturedAt: now
            )

            snapshot = built
            lastUpdate = now
            lastError = nil
            appendHistory(from: built)
            schedulePingsIfNeeded(for: built)
            schedulePublicIPLookupIfNeeded(for: built)
            publishToWidget(built, now: now)
        } catch {
            handle(error)
        }
    }

    private func appendHistory(from snapshot: DashboardSnapshot) {
        for interface in snapshot.interfaces {
            var entry = history[interface.name] ?? TrafficHistory()
            entry.append(
                TrafficRate(
                    rxBitsPerSecond: interface.rxBitsPerSecond,
                    txBitsPerSecond: interface.txBitsPerSecond
                )
            )
            history[interface.name] = entry
        }
    }

    private func handle(_ error: Error) {
        let message = (error as? RouterError)?.errorDescription ?? error.localizedDescription
        lastError = message

        // Keep the last good reading on screen; only fall back to an empty
        // offline snapshot when we never managed to load anything.
        if snapshot.interfaces.isEmpty {
            snapshot = .offline(host: config.host, message: message)
        }
    }

    // MARK: - Ping

    /// Pings run on their own task: a dead WAN takes seconds to time out and
    /// must not stall the 2-second counter poll.
    private func schedulePingsIfNeeded(for snapshot: DashboardSnapshot) {
        guard pingTask == nil else { return }
        guard Date().timeIntervalSince(lastPingAt) >= config.pingInterval else { return }

        let targets = snapshot.wanInterfaces.map(\.name)
        guard !targets.isEmpty else { return }

        pingTask = Task { [weak self] in
            guard let self else { return }
            // Ping each WAN's modem gateway instead of a single internet host,
            // because ECMP on the shared /24 subnet breaks router-originated
            // internet pings. The modem gateway is always directly reachable.
            var results: [String: PingOutcome] = [:]
            for name in targets {
                let addr = self.modemGateway(for: name) ?? self.config.pingTarget
                results[name] = await self.runSinglePing(target: name, address: addr)
            }
            self.pingResults = results
            self.lastPingAt = Date()
            self.pingTask = nil
        }
    }

    private func runPings(targets: [String], address: String) async -> [String: PingOutcome] {
        await withTaskGroup(of: (String, PingOutcome).self) { group in
            for name in targets {
                group.addTask { [client] in
                    do {
                        let outcome = try await client.ping(address: address, viaInterface: name, count: 3)
                        return (name, outcome)
                    } catch {
                        return (name, .unreachable)
                    }
                }
            }
            var results: [String: PingOutcome] = [:]
            for await (name, outcome) in group {
                results[name] = outcome
            }
            return results
        }
    }

    func pingNow() {
        lastPingAt = .distantPast
        schedulePingsIfNeeded(for: snapshot)
    }

    /// The upstream gateway reachable through `interfaceName`, learned from the
    /// routing table on each poll.
    ///
    /// Pinging the modem rather than a public address is what makes a per-WAN
    /// health check trustworthy when both uplinks share one subnet: with ECMP
    /// in play, a ping aimed at the internet can leave by either link and
    /// report the wrong one as healthy. Falls back to `config.pingTarget` when
    /// the routing table does not name a gateway for the interface.
    private func modemGateway(for interfaceName: String) -> String? {
        gatewaysByInterface[interfaceName]
    }

    // MARK: - Public address per uplink

    /// Asks the router what public address each WAN presents. Runs on its own
    /// slow timer and never blocks the counter poll — every lookup leaves the
    /// network and can take seconds on a degraded link.
    private func schedulePublicIPLookupIfNeeded(for snapshot: DashboardSnapshot) {
        guard publicIPTask == nil else { return }
        let echoURL = config.publicIPEchoURL.trimmingCharacters(in: .whitespaces)
        guard !echoURL.isEmpty else { return }
        guard Date().timeIntervalSince(lastPublicIPAt) >= config.publicIPInterval else { return }

        // The source address is what an output-chain routing mark keys on, so
        // an uplink with no address of its own cannot be probed.
        let targets: [(name: String, source: String)] = snapshot.wanInterfaces.compactMap {
            guard !$0.isDisabled, let address = $0.ipAddress else { return nil }
            return ($0.name, address)
        }
        guard !targets.isEmpty else { return }

        lastPublicIPAt = Date()
        publicIPTask = Task { [weak self] in
            guard let self else { return }
            let client = self.client
            let resolved = await withTaskGroup(of: (String, String?).self) { group in
                for target in targets {
                    group.addTask {
                        let value = try? await client.publicAddress(
                            sourceAddress: target.source,
                            echoURL: echoURL
                        )
                        return (target.name, value)
                    }
                }
                var found: [String: String] = [:]
                for await (name, value) in group {
                    if let value { found[name] = value }
                }
                return found
            }

            guard !Task.isCancelled else { return }
            // Keep the previous answer for a link that failed this round rather
            // than blanking a field the operator may be reading.
            for (name, value) in resolved { self.publicAddresses[name] = value }
            self.snapshot = self.snapshot.applyingPublicAddresses(self.publicAddresses)
            self.publicIPTask = nil
        }
    }

    func refreshPublicAddresses() {
        lastPublicIPAt = .distantPast
        schedulePublicIPLookupIfNeeded(for: snapshot)
    }

    /// Maps each interface to the gateway address a default route uses through
    /// it, e.g. an `immediate-gw` of `192.0.2.1%ether1` yields `ether1` ->
    /// `192.0.2.1`. Lower distances win so the primary gateway is preferred.
    static func gateways(from routes: [RouterRoute]) -> [String: String] {
        var result: [String: String] = [:]
        for route in routes.filter({ $0.isDefaultRoute }).sorted(by: { $0.distance < $1.distance }) {
            guard let gateway = route.gatewayAddress else { continue }
            for name in route.resolvedInterfaceNames where result[name] == nil {
                result[name] = gateway
            }
        }
        return result
    }

    /// Pings a single target through a specific interface.
    private func runSinglePing(target name: String, address: String) async -> PingOutcome {
        do {
            return try await client.ping(address: address, viaInterface: name, count: 3)
        } catch {
            return .unreachable
        }
    }

    /// Runs a single on-demand ping out of one interface. Each interface gets
    /// its own task so a stalled WAN never blocks a test on the other one.
    func testConnection(forInterface name: String) {
        guard pingTestTasks[name] == nil else { return }

        // Ping the modem gateway, not an internet host. With both WANs on the
        // same /24 subnet, router-originated internet pings fail due to ECMP
        // return-path issues, but the modem gateway is always reachable on its
        // own interface.
        let address = modemGateway(for: name) ?? config.pingTarget
        connectionTests[name] = .running
        pingTestTasks[name] = Task { [weak self] in
            guard let self else { return }
            let outcome: PingOutcome
            do {
                outcome = try await self.client.ping(address: address, viaInterface: name, count: 3)
            } catch {
                outcome = .unreachable
            }

            self.pingTestTasks[name] = nil
            guard !Task.isCancelled else {
                self.connectionTests[name] = nil
                return
            }

            // Feed the background result cache too, so the next poll keeps the
            // fresher reading instead of reverting to the stale one.
            self.pingResults[name] = outcome
            self.connectionTests[name] = .finished(outcome)
            self.snapshot = self.snapshot.applyingPing(outcome, toInterface: name)
        }
    }

    func connectionTest(for name: String) -> ConnectionTestState? {
        connectionTests[name]
    }

    // MARK: - Enable / disable

    /// Enables or disables one interface on its own. The router keeps a
    /// distance-2 failover default in each policy table, so dropping one WAN
    /// re-routes its share through the other instead of blackholing it.
    func setInterfaceDisabled(_ disabled: Bool, forInterface name: String) {
        guard toggleTasks[name] == nil else { return }
        // Writing through the live `.id` keeps working if the interface is
        // renamed between polls; the name is only a fallback.
        let identifier = interfaceIDs[name] ?? name
        pendingToggles.insert(name)
        toggleTasks[name] = Task { [weak self] in
            guard let self else { return }
            var failure: String?
            do {
                try await self.client.setInterfaceDisabled(disabled, interface: identifier)
            } catch {
                failure = (error as? RouterError)?.errorDescription ?? error.localizedDescription
            }
            self.toggleTasks[name] = nil
            self.pendingToggles.remove(name)
            if let failure {
                self.lastError = failure
            } else {
                await self.refresh()
            }
        }
    }

    func isTogglingInterface(_ name: String) -> Bool {
        pendingToggles.contains(name)
    }

    // MARK: - Widget hand-off

    private func publishToWidget(_ snapshot: DashboardSnapshot, now: Date) {
        guard now.timeIntervalSince(lastSnapshotWriteAt) >= snapshotWriteInterval else { return }
        lastSnapshotWriteAt = now
        try? SharedStore.writeSnapshot(snapshot)

        guard now.timeIntervalSince(lastWidgetReloadAt) >= widgetReloadInterval else { return }
        lastWidgetReloadAt = now
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Derived display state

    var menuBarTitle: String {
        guard let wan = snapshot.primaryWAN else { return "—" }
        return "\(Formatting.compactBitsPerSecond(wan.rxBitsPerSecond))"
            + " / \(Formatting.compactBitsPerSecond(wan.txBitsPerSecond))"
    }

    var connectionSummary: String {
        if let lastError { return lastError }
        guard let lastUpdate else { return "Connecting to \(config.host)…" }
        return "Updated \(Formatting.age(of: lastUpdate))"
    }

    var isHealthy: Bool { lastError == nil && lastUpdate != nil }

    func history(for name: String) -> TrafficHistory {
        history[name] ?? TrafficHistory()
    }
}
