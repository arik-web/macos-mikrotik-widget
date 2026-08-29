import Foundation
import WidgetKit
import MikroTikKit

/// Timeline entry carrying a full dashboard snapshot.
struct TrafficEntry: TimelineEntry {
    let date: Date
    let snapshot: DashboardSnapshot

    static func placeholder(now: Date = Date()) -> TrafficEntry {
        TrafficEntry(date: now, snapshot: .placeholder(now: now))
    }
}

/// Feeds the widget from the snapshot the app writes to the shared container.
///
/// If the app has not run recently the provider talks to the router itself,
/// so the widget keeps working when the dashboard window is closed.
struct TrafficTimelineProvider: TimelineProvider {
    /// Widget refreshes are throttled by the system; five minutes is the
    /// practical floor for a non-Live-Activity widget.
    static let refreshInterval: TimeInterval = 300
    /// Beyond this age the stored snapshot is not worth showing.
    static let staleAfter: TimeInterval = 240

    func placeholder(in context: Context) -> TrafficEntry {
        .placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (TrafficEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder())
            return
        }
        Task {
            completion(await currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrafficEntry>) -> Void) {
        Task {
            let entry = await currentEntry()
            let next = Date().addingTimeInterval(Self.refreshInterval)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func currentEntry() async -> TrafficEntry {
        let now = Date()

        if let stored = SharedStore.readSnapshot(),
           !stored.isStale(now: now, tolerance: Self.staleAfter) {
            return TrafficEntry(date: now, snapshot: stored)
        }

        if let fetched = await fetchDirectly(now: now) {
            return TrafficEntry(date: now, snapshot: fetched)
        }

        // Nothing fresh and no reachable router: show the last known values
        // rather than an empty card, flagged as unreachable.
        if let stored = SharedStore.readSnapshot() {
            return TrafficEntry(
                date: now,
                snapshot: DashboardSnapshot(
                    capturedAt: stored.capturedAt,
                    routerHost: stored.routerHost,
                    isReachable: false,
                    errorMessage: "Router unreachable",
                    interfaces: stored.interfaces,
                    activeWANs: stored.activeWANs
                )
            )
        }

        let config = RouterConfigStore.load()
        return TrafficEntry(
            date: now,
            snapshot: .offline(host: config.host, message: "No data yet", now: now)
        )
    }

    /// One-shot poll: two counter reads a second apart give the widget a real
    /// rate instead of a flat zero.
    private func fetchDirectly(now: Date) async -> DashboardSnapshot? {
        let config = RouterConfigStore.load()
        let client = RouterClient(config: config, credentials: CredentialStore.load())

        do {
            let first = try await client.fetchState()
            var tracker = RateTracker()
            let firstTime = Date()
            for interface in first.interfaces {
                _ = tracker.update(
                    interfaceName: interface.name,
                    sample: CounterSample(
                        rxBytes: interface.rxBytes,
                        txBytes: interface.txBytes,
                        timestamp: firstTime
                    )
                )
            }

            try await Task.sleep(nanoseconds: 1_000_000_000)

            let second = try await client.fetchState()
            let secondTime = Date()
            var rates: [String: TrafficRate] = [:]
            for interface in second.interfaces {
                rates[interface.name] = tracker.update(
                    interfaceName: interface.name,
                    sample: CounterSample(
                        rxBytes: interface.rxBytes,
                        txBytes: interface.txBytes,
                        timestamp: secondTime
                    )
                )
            }

            return SnapshotBuilder.build(
                config: config,
                state: second,
                rates: rates,
                pings: [:],
                capturedAt: now
            )
        } catch {
            return nil
        }
    }
}
