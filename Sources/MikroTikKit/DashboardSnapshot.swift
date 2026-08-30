import Foundation

public enum InterfaceRole: String, Codable, Equatable {
    case wan
    case lan
    case other
}

public enum PingStatus: String, Codable, Equatable {
    case unknown
    case up
    case down
}

/// One interface as rendered by the dashboard and the widget.
public struct InterfaceSnapshot: Codable, Equatable, Identifiable {
    public var id: String { name }

    public let name: String
    public let ipAddress: String?
    /// Public address the ISP presents for this uplink, when known.
    public let publicIPAddress: String?
    public let isRunning: Bool
    public let isDisabled: Bool
    public let rxBytes: UInt64
    public let txBytes: UInt64
    public let rxBitsPerSecond: Double
    public let txBitsPerSecond: Double
    public let role: InterfaceRole
    /// True when this interface carries the active default route.
    public let isActiveGateway: Bool
    public let pingStatus: PingStatus
    public let pingLatency: TimeInterval?

    public init(
        name: String,
        ipAddress: String?,
        publicIPAddress: String? = nil,
        isRunning: Bool,
        isDisabled: Bool,
        rxBytes: UInt64,
        txBytes: UInt64,
        rxBitsPerSecond: Double,
        txBitsPerSecond: Double,
        role: InterfaceRole,
        isActiveGateway: Bool,
        pingStatus: PingStatus,
        pingLatency: TimeInterval?
    ) {
        self.name = name
        self.ipAddress = ipAddress
        self.publicIPAddress = publicIPAddress
        self.isRunning = isRunning
        self.isDisabled = isDisabled
        self.rxBytes = rxBytes
        self.txBytes = txBytes
        self.rxBitsPerSecond = rxBitsPerSecond
        self.txBitsPerSecond = txBitsPerSecond
        self.role = role
        self.isActiveGateway = isActiveGateway
        self.pingStatus = pingStatus
        self.pingLatency = pingLatency
    }

    public var totalBytes: UInt64 { rxBytes &+ txBytes }

    /// Copy carrying the result of a fresh ping, leaving counters untouched.
    public func applyingPing(_ outcome: PingOutcome) -> InterfaceSnapshot {
        InterfaceSnapshot(
            name: name,
            ipAddress: ipAddress,
            publicIPAddress: publicIPAddress,
            isRunning: isRunning,
            isDisabled: isDisabled,
            rxBytes: rxBytes,
            txBytes: txBytes,
            rxBitsPerSecond: rxBitsPerSecond,
            txBitsPerSecond: txBitsPerSecond,
            role: role,
            isActiveGateway: isActiveGateway,
            pingStatus: outcome.status,
            pingLatency: outcome.averageLatency
        )
    }

    /// Copy carrying a freshly resolved public address. A nil argument keeps
    /// the previous value: a lookup that failed this round should not blank a
    /// field the operator may be reading.
    public func applyingPublicAddress(_ address: String?) -> InterfaceSnapshot {
        guard let address else { return self }
        return InterfaceSnapshot(
            name: name,
            ipAddress: ipAddress,
            publicIPAddress: address,
            isRunning: isRunning,
            isDisabled: isDisabled,
            rxBytes: rxBytes,
            txBytes: txBytes,
            rxBitsPerSecond: rxBitsPerSecond,
            txBitsPerSecond: txBitsPerSecond,
            role: role,
            isActiveGateway: isActiveGateway,
            pingStatus: pingStatus,
            pingLatency: pingLatency
        )
    }

    /// Link is administratively enabled and physically up.
    public var isUp: Bool { isRunning && !isDisabled }

    /// A WAN is only "healthy" once it also answers a ping.
    public var isHealthy: Bool {
        guard isUp else { return false }
        return role == .wan ? pingStatus != .down : true
    }
}

/// The complete state one poll produces. Written to disk by the app and read
/// back by the widget extension.
public struct DashboardSnapshot: Codable, Equatable {
    public let capturedAt: Date
    public let routerHost: String
    public let isReachable: Bool
    public let errorMessage: String?
    public let interfaces: [InterfaceSnapshot]
    /// Interfaces carrying the active default route. Holds more than one when
    /// the router load-balances across both uplinks.
    public let activeWANs: [String]

    public init(
        capturedAt: Date,
        routerHost: String,
        isReachable: Bool,
        errorMessage: String? = nil,
        interfaces: [InterfaceSnapshot] = [],
        activeWANs: [String] = []
    ) {
        self.capturedAt = capturedAt
        self.routerHost = routerHost
        self.isReachable = isReachable
        self.errorMessage = errorMessage
        self.interfaces = interfaces
        self.activeWANs = activeWANs
    }

    /// Single headline uplink, for places with room for only one name.
    public var activeWAN: String? { activeWANs.first }

    /// Human-readable active route, e.g. `WAN1` or `WAN1 + WAN2`.
    public var activeRouteLabel: String {
        activeWANs.isEmpty ? "unknown" : activeWANs.joined(separator: " + ")
    }

    /// Copy with `outcome` applied to one interface; other interfaces and the
    /// capture metadata are preserved so a ping cannot age a fresh reading.
    public func applyingPing(_ outcome: PingOutcome, toInterface name: String) -> DashboardSnapshot {
        DashboardSnapshot(
            capturedAt: capturedAt,
            routerHost: routerHost,
            isReachable: isReachable,
            errorMessage: errorMessage,
            interfaces: interfaces.map { $0.name == name ? $0.applyingPing(outcome) : $0 },
            activeWANs: activeWANs
        )
    }

    public func interface(named name: String) -> InterfaceSnapshot? {
        interfaces.first { $0.name == name }
    }

    public var wanInterfaces: [InterfaceSnapshot] {
        interfaces.filter { $0.role == .wan }
    }

    public var lanInterfaces: [InterfaceSnapshot] {
        interfaces.filter { $0.role == .lan }
    }

    /// The interface the widget should headline: the busiest active gateway
    /// when one is known, otherwise the busiest healthy WAN.
    public var primaryWAN: InterfaceSnapshot? {
        let active = activeWANs.compactMap { interface(named: $0) }
        if !active.isEmpty {
            return active.max { lhs, rhs in
                (lhs.rxBitsPerSecond + lhs.txBitsPerSecond) < (rhs.rxBitsPerSecond + rhs.txBitsPerSecond)
            }
        }
        return wanInterfaces
            .filter(\.isUp)
            .max { lhs, rhs in
                (lhs.rxBitsPerSecond + lhs.txBitsPerSecond) < (rhs.rxBitsPerSecond + rhs.txBitsPerSecond)
            }
    }

    public var totalRxBytes: UInt64 {
        wanInterfaces.reduce(UInt64(0)) { $0 &+ $1.rxBytes }
    }

    public var totalTxBytes: UInt64 {
        wanInterfaces.reduce(UInt64(0)) { $0 &+ $1.txBytes }
    }

    public func isStale(now: Date = Date(), tolerance: TimeInterval = 600) -> Bool {
        now.timeIntervalSince(capturedAt) > tolerance
    }

    /// Returns a copy with public addresses merged in, leaving every other
    /// field untouched.
    public func applyingPublicAddresses(_ addresses: [String: String]) -> DashboardSnapshot {
        DashboardSnapshot(
            capturedAt: capturedAt,
            routerHost: routerHost,
            isReachable: isReachable,
            errorMessage: errorMessage,
            interfaces: interfaces.map { $0.applyingPublicAddress(addresses[$0.name]) },
            activeWANs: activeWANs
        )
    }

    /// Sample data for widget galleries and SwiftUI previews.
    public static func placeholder(now: Date = Date()) -> DashboardSnapshot {
        DashboardSnapshot(
            capturedAt: now,
            routerHost: "192.168.88.1",
            isReachable: true,
            interfaces: [
                InterfaceSnapshot(
                    name: "WAN1",
                    ipAddress: "192.168.100.2",
                    isRunning: true,
                    isDisabled: false,
                    rxBytes: 812_345_678_901,
                    txBytes: 94_567_890_123,
                    rxBitsPerSecond: 48_500_000,
                    txBitsPerSecond: 6_200_000,
                    role: .wan,
                    isActiveGateway: true,
                    pingStatus: .up,
                    pingLatency: 0.012
                ),
                InterfaceSnapshot(
                    name: "WAN2",
                    ipAddress: "192.168.100.131",
                    isRunning: true,
                    isDisabled: false,
                    rxBytes: 233_456_789_012,
                    txBytes: 21_234_567_890,
                    rxBitsPerSecond: 1_100_000,
                    txBitsPerSecond: 380_000,
                    role: .wan,
                    isActiveGateway: false,
                    pingStatus: .up,
                    pingLatency: 0.028
                ),
                InterfaceSnapshot(
                    name: "bridge1",
                    ipAddress: "192.168.88.1",
                    isRunning: true,
                    isDisabled: false,
                    rxBytes: 1_402_345_678_901,
                    txBytes: 1_812_345_678_901,
                    rxBitsPerSecond: 56_000_000,
                    txBitsPerSecond: 52_000_000,
                    role: .lan,
                    isActiveGateway: false,
                    pingStatus: .unknown,
                    pingLatency: nil
                ),
            ],
            activeWANs: ["WAN1"]
        )
    }

    public static func offline(host: String, message: String, now: Date = Date()) -> DashboardSnapshot {
        DashboardSnapshot(
            capturedAt: now,
            routerHost: host,
            isReachable: false,
            errorMessage: message
        )
    }
}
