import Foundation

/// Everything the dashboard needs to reach the router, minus the password.
public struct RouterConfig: Codable, Equatable {
    public var host: String
    public var useTLS: Bool
    public var username: String
    /// Seconds between counter polls.
    public var pollInterval: TimeInterval
    /// Seconds between reachability pings (much slower than the counter poll).
    public var pingInterval: TimeInterval
    public var pingTarget: String
    /// Interfaces treated as WAN uplinks, in display order.
    public var wanInterfaceNames: [String]
    /// Interfaces treated as the LAN side.
    public var lanInterfaceNames: [String]
    /// When false, unconfigured interfaces only appear if they carry an IP,
    /// which hides bridge member ports and empty SFP cages.
    public var showAllInterfaces: Bool
    /// Echo service the router fetches to learn each uplink's public address.
    /// Empty disables the lookup entirely — it is the only part of this app
    /// that talks to a third party.
    public var publicIPEchoURL: String
    /// Seconds between public-address lookups. Far slower than the counter
    /// poll: the address rarely changes and each check leaves the network.
    public var publicIPInterval: TimeInterval

    public init(
        host: String = "192.168.88.1",
        useTLS: Bool = false,
        username: String = "admin",
        pollInterval: TimeInterval = 2,
        pingInterval: TimeInterval = 30,
        pingTarget: String = "8.8.8.8",
        wanInterfaceNames: [String] = ["WAN1", "WAN2"],
        lanInterfaceNames: [String] = ["bridge1"],
        showAllInterfaces: Bool = false,
        publicIPEchoURL: String = "http://ifconfig.me/ip",
        publicIPInterval: TimeInterval = 300
    ) {
        self.host = host
        self.useTLS = useTLS
        self.username = username
        self.pollInterval = pollInterval
        self.pingInterval = pingInterval
        self.pingTarget = pingTarget
        self.wanInterfaceNames = wanInterfaceNames
        self.lanInterfaceNames = lanInterfaceNames
        self.showAllInterfaces = showAllInterfaces
        self.publicIPEchoURL = publicIPEchoURL
        self.publicIPInterval = publicIPInterval
    }

    public static let `default` = RouterConfig()

    public var baseURL: URL? {
        URL(string: "\(useTLS ? "https" : "http")://\(host)/rest")
    }

    public func role(for interfaceName: String) -> InterfaceRole {
        if wanInterfaceNames.contains(interfaceName) { return .wan }
        if lanInterfaceNames.contains(interfaceName) { return .lan }
        return .other
    }

    /// Sort key that keeps WANs first, then the LAN, then everything else,
    /// preserving the configured order inside each group.
    public func displayOrder(for interfaceName: String) -> Int {
        if let index = wanInterfaceNames.firstIndex(of: interfaceName) { return index }
        if let index = lanInterfaceNames.firstIndex(of: interfaceName) { return 100 + index }
        return 1000
    }
}

/// Loads and persists `RouterConfig` in the shared defaults domain so the
/// widget extension sees the same host as the app.
public enum RouterConfigStore {
    static let defaultsKey = "io.github.macosmikrotikwidget.config"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStore.appGroupIdentifier) ?? .standard
    }

    public static func load() -> RouterConfig {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let config = try? JSONDecoder().decode(RouterConfig.self, from: data)
        else {
            return .default
        }
        return config
    }

    public static func save(_ config: RouterConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
