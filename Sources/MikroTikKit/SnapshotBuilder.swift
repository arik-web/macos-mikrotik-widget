import Foundation

/// IPv4 helpers used to match a gateway address back to the interface that
/// owns its subnet.
public enum IPv4 {
    public static func parse(_ address: String) -> UInt32? {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            result = (result << 8) | octet
        }
        return result
    }

    /// True when `address` falls inside `cidr` (e.g. `192.168.100.0/24`).
    public static func cidr(_ cidr: String, contains address: String) -> Bool {
        let components = cidr.split(separator: "/")
        guard
            let network = components.first.map(String.init).flatMap(parse(_:)),
            let target = parse(address)
        else { return false }

        let prefix = components.dropFirst().first.flatMap { Int($0) } ?? 32
        guard (0...32).contains(prefix) else { return false }
        guard prefix > 0 else { return true }

        let mask: UInt32 = prefix == 32 ? .max : ~(UInt32.max >> UInt32(prefix))
        return (network & mask) == (target & mask)
    }
}

/// Turns raw router collections plus computed rates into a `DashboardSnapshot`.
/// Pure and synchronous so the aggregation rules can be unit tested.
public enum SnapshotBuilder {
    public static func build(
        config: RouterConfig,
        state: RouterState,
        rates: [String: TrafficRate],
        pings: [String: PingOutcome],
        capturedAt: Date
    ) -> DashboardSnapshot {
        let knownNames = Set(state.interfaces.map(\.name))
        let activeWANs = activeGatewayInterfaces(
            routes: state.routes,
            addresses: state.addresses,
            knownInterfaces: knownNames
        )
        let activeSet = Set(activeWANs)
        let addressed = Set(state.addresses.filter { !$0.isDisabled }.map(\.interfaceName))

        let snapshots = state.interfaces
            .filter { shouldDisplay($0, config: config, hasAddress: addressed.contains($0.name)) }
            .map { interface -> InterfaceSnapshot in
                let rate = rates[interface.name] ?? .zero
                let ping = pings[interface.name]
                return InterfaceSnapshot(
                    name: interface.name,
                    ipAddress: primaryAddress(for: interface.name, in: state.addresses),
                    isRunning: interface.isRunning,
                    isDisabled: interface.isDisabled,
                    rxBytes: interface.rxBytes,
                    txBytes: interface.txBytes,
                    rxBitsPerSecond: rate.rxBitsPerSecond,
                    txBitsPerSecond: rate.txBitsPerSecond,
                    role: config.role(for: interface.name),
                    isActiveGateway: activeSet.contains(interface.name),
                    pingStatus: ping?.status ?? .unknown,
                    pingLatency: ping?.averageLatency
                )
            }
            .sorted { lhs, rhs in
                let left = config.displayOrder(for: lhs.name)
                let right = config.displayOrder(for: rhs.name)
                return left == right ? lhs.name < rhs.name : left < right
            }

        return DashboardSnapshot(
            capturedAt: capturedAt,
            routerHost: config.host,
            isReachable: true,
            errorMessage: nil,
            interfaces: snapshots,
            activeWANs: activeWANs
        )
    }

    /// Decides what earns a card.
    ///
    /// A real router exposes a lot of noise: bridge member ports, loopback,
    /// unused SFP cages. Configured WAN/LAN interfaces always show, and
    /// anything else has to carry an IP address to earn its place — which is
    /// what distinguishes a routed interface from a bridge slave.
    public static func shouldDisplay(
        _ interface: RouterInterface,
        config: RouterConfig,
        hasAddress: Bool
    ) -> Bool {
        if config.role(for: interface.name) != .other { return true }
        if config.showAllInterfaces { return interface.type != "loopback" }
        return hasAddress
    }

    static func primaryAddress(for interfaceName: String, in addresses: [RouterAddress]) -> String? {
        let matches = addresses.filter { $0.interfaceName == interfaceName && !$0.isDisabled }
        // A static address describes the interface better than a DHCP lease.
        let preferred = matches.first { !$0.isDynamic } ?? matches.first
        return preferred?.ipOnly
    }

    /// Resolves which interfaces carry the active default route.
    ///
    /// Returns more than one name for a load-balanced (ECMP) route, where
    /// RouterOS really is splitting traffic across both uplinks.
    ///
    /// Only the `main` routing table is considered — a policy-routing setup
    /// also defines per-WAN tables whose default routes say nothing about
    /// where ordinary LAN traffic goes.
    ///
    /// `immediate-gw` is authoritative when RouterOS fills it in. Subnet
    /// matching is a last resort, and only when exactly one interface owns the
    /// gateway's subnet: both WANs here sit in 192.168.100.0/24, where a guess
    /// would be wrong half the time.
    public static func activeGatewayInterfaces(
        routes: [RouterRoute],
        addresses: [RouterAddress],
        knownInterfaces: Set<String>
    ) -> [String] {
        let candidates = routes
            .filter { $0.isDefaultRoute && $0.isUsable && $0.isMainTable }
            .sorted { $0.distance < $1.distance }

        for route in candidates {
            let names = route.resolvedInterfaceNames.filter { knownInterfaces.contains($0) }
            if !names.isEmpty { return names }
        }

        for route in candidates {
            guard let gateway = route.gatewayAddress else { continue }
            // Some configurations name the interface directly as the gateway.
            if knownInterfaces.contains(gateway) { return [gateway] }

            let owners = Set(
                addresses
                    .filter { !$0.isDisabled && IPv4.cidr($0.address, contains: gateway) }
                    .map(\.interfaceName)
            )
            if owners.count == 1, let name = owners.first, knownInterfaces.contains(name) {
                return [name]
            }
        }

        return []
    }
}
