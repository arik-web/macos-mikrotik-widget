import Foundation

// MARK: - Interfaces

/// A row from `GET /rest/interface`.
public struct RouterInterface: Identifiable, Equatable, Codable {
    public let id: String
    public let name: String
    public let type: String
    public let isRunning: Bool
    public let isDisabled: Bool
    public let rxBytes: UInt64
    public let txBytes: UInt64
    public let macAddress: String?
    public let comment: String?

    public init(
        id: String,
        name: String,
        type: String,
        isRunning: Bool,
        isDisabled: Bool,
        rxBytes: UInt64,
        txBytes: UInt64,
        macAddress: String? = nil,
        comment: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isRunning = isRunning
        self.isDisabled = isDisabled
        self.rxBytes = rxBytes
        self.txBytes = txBytes
        self.macAddress = macAddress
        self.comment = comment
    }

    /// Fails only when the record carries no interface name, which makes the
    /// row unusable for every downstream lookup.
    public init?(record: RouterRecord) {
        guard let name = record.string("name") else { return nil }
        self.init(
            id: record.string(".id") ?? name,
            name: name,
            type: record.string("type") ?? "unknown",
            isRunning: record.flag("running"),
            isDisabled: record.flag("disabled"),
            rxBytes: record.uint64("rx-byte") ?? 0,
            txBytes: record.uint64("tx-byte") ?? 0,
            macAddress: record.string("mac-address"),
            comment: record.string("comment")
        )
    }

    public var counters: CounterSample {
        CounterSample(rxBytes: rxBytes, txBytes: txBytes, timestamp: Date())
    }
}

// MARK: - Addresses

/// A row from `GET /rest/ip/address`.
public struct RouterAddress: Identifiable, Equatable, Codable {
    public let id: String
    /// Full CIDR form, e.g. `192.168.100.2/24`.
    public let address: String
    public let network: String?
    public let interfaceName: String
    public let isDisabled: Bool
    public let isDynamic: Bool

    public init(
        id: String,
        address: String,
        network: String? = nil,
        interfaceName: String,
        isDisabled: Bool = false,
        isDynamic: Bool = false
    ) {
        self.id = id
        self.address = address
        self.network = network
        self.interfaceName = interfaceName
        self.isDisabled = isDisabled
        self.isDynamic = isDynamic
    }

    public init?(record: RouterRecord) {
        guard let address = record.string("address") else { return nil }
        // `actual-interface` resolves bridge members; prefer it when present.
        guard let interfaceName = record.string("actual-interface") ?? record.string("interface") else {
            return nil
        }
        self.init(
            id: record.string(".id") ?? address,
            address: address,
            network: record.string("network"),
            interfaceName: interfaceName,
            isDisabled: record.flag("disabled"),
            isDynamic: record.flag("dynamic")
        )
    }

    /// The address without its prefix length, e.g. `192.168.100.2`.
    public var ipOnly: String {
        address.split(separator: "/").first.map(String.init) ?? address
    }

    public var prefixLength: Int? {
        address.split(separator: "/").dropFirst().first.flatMap { Int($0) }
    }
}

// MARK: - Routes

/// A row from `GET /rest/ip/route`.
public struct RouterRoute: Identifiable, Equatable, Codable {
    public let id: String
    public let dstAddress: String
    public let gateway: String?
    /// Outgoing next hops resolved by RouterOS. A load-balanced route lists
    /// every ECMP leg here, comma separated:
    /// `192.168.100.254%WAN1,192.168.100.254%WAN2`.
    public let immediateGateway: String?
    public let distance: Int
    public let isActive: Bool
    /// RouterOS reports `inactive` separately, and omits `active` entirely on
    /// routes that are not in use.
    public let isInactive: Bool
    public let isDisabled: Bool
    public let isDynamic: Bool
    public let isECMP: Bool
    /// Routers with policy routing expose several tables; only `main` decides
    /// where unclassified LAN traffic goes.
    public let routingTable: String?
    public let checkGateway: String?

    public init(
        id: String,
        dstAddress: String,
        gateway: String? = nil,
        immediateGateway: String? = nil,
        distance: Int = 1,
        isActive: Bool = false,
        isInactive: Bool = false,
        isDisabled: Bool = false,
        isDynamic: Bool = false,
        isECMP: Bool = false,
        routingTable: String? = nil,
        checkGateway: String? = nil
    ) {
        self.id = id
        self.dstAddress = dstAddress
        self.gateway = gateway
        self.immediateGateway = immediateGateway
        self.distance = distance
        self.isActive = isActive
        self.isInactive = isInactive
        self.isDisabled = isDisabled
        self.isDynamic = isDynamic
        self.isECMP = isECMP
        self.routingTable = routingTable
        self.checkGateway = checkGateway
    }

    public init?(record: RouterRecord) {
        guard let dstAddress = record.string("dst-address") else { return nil }
        self.init(
            id: record.string(".id") ?? dstAddress,
            dstAddress: dstAddress,
            gateway: record.string("gateway"),
            immediateGateway: record.string("immediate-gw"),
            distance: record.int("distance") ?? 1,
            isActive: record.flag("active"),
            isInactive: record.flag("inactive"),
            isDisabled: record.flag("disabled"),
            isDynamic: record.flag("dynamic"),
            isECMP: record.flag("ecmp"),
            routingTable: record.string("routing-table"),
            checkGateway: record.string("check-gateway")
        )
    }

    public var isDefaultRoute: Bool {
        dstAddress.trimmingCharacters(in: .whitespaces) == "0.0.0.0/0"
    }

    /// A route actually carrying traffic right now.
    public var isUsable: Bool {
        isActive && !isInactive && !isDisabled
    }

    /// Routes with no explicit table belong to `main`.
    public var isMainTable: Bool {
        routingTable == nil || routingTable == "main"
    }

    /// Every outgoing interface for this route, in RouterOS order and
    /// deduplicated. An ECMP default route legitimately returns more than one.
    public var resolvedInterfaceNames: [String] {
        for candidate in [immediateGateway, gateway] {
            guard let candidate, !candidate.isEmpty else { continue }

            var unique: [String] = []
            for leg in candidate.split(separator: ",") {
                guard let separator = leg.firstIndex(of: "%") else { continue }
                let name = String(leg[leg.index(after: separator)...])
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !unique.contains(name) {
                    unique.append(name)
                }
            }
            if !unique.isEmpty { return unique }
        }
        return []
    }

    public var resolvedInterfaceName: String? {
        resolvedInterfaceNames.first
    }

    /// First gateway IP, with any `%interface` suffix stripped.
    public var gatewayAddress: String? {
        guard let gateway, !gateway.isEmpty else { return nil }
        let first = gateway.split(separator: ",").first.map(String.init) ?? gateway
        return first.split(separator: "%").first.map(String.init)
    }
}

// MARK: - Ping

/// Aggregated result of `POST /rest/tool/ping`.
public struct PingOutcome: Equatable, Codable {
    public let sent: Int
    public let received: Int
    /// Average round-trip time in seconds, when at least one reply arrived.
    public let averageLatency: TimeInterval?

    public init(sent: Int, received: Int, averageLatency: TimeInterval?) {
        self.sent = sent
        self.received = received
        self.averageLatency = averageLatency
    }

    public static let unreachable = PingOutcome(sent: 0, received: 0, averageLatency: nil)

    public var isReachable: Bool { received > 0 }

    public var packetLoss: Double {
        guard sent > 0 else { return 1 }
        return Double(sent - received) / Double(sent)
    }

    public var status: PingStatus { isReachable ? .up : .down }

    /// Folds the per-sequence records RouterOS returns into a single result.
    ///
    /// Every record carries a cumulative `sent`/`received` pair, so the last
    /// record wins; when those columns are missing we count replies instead.
    public static func aggregate(records: [RouterRecord]) -> PingOutcome {
        guard !records.isEmpty else { return .unreachable }

        // A failed probe still reports a `time`: an ICMP "host unreachable"
        // answer is timed like any other. Only records with no `status` are
        // real echo replies, so timing anything else inflates the latency.
        var latencies: [TimeInterval] = []
        for record in records where record.string("status") == nil {
            if let raw = record.string("time"), let seconds = RouterDuration.parse(raw) {
                latencies.append(seconds)
            }
        }

        let last = records[records.count - 1]
        let sent = max(last.int("sent") ?? records.count, 0)
        let received = max(min(last.int("received") ?? latencies.count, sent), 0)

        var average: TimeInterval?
        if received > 0 {
            // RouterOS computes the summary itself on the final record.
            if let summary = last.string("avg-rtt"), let seconds = RouterDuration.parse(summary) {
                average = seconds
            } else if !latencies.isEmpty {
                average = latencies.reduce(0, +) / Double(latencies.count)
            }
        }

        return PingOutcome(sent: sent, received: received, averageLatency: average)
    }
}

// MARK: - Durations

/// Named to avoid colliding with the standard library's `Swift.Duration`.
public enum RouterDuration {
    /// Parses a RouterOS duration such as `12ms`, `1s200ms` or `450us`
    /// into seconds. Returns `nil` when nothing parseable is found.
    public static func parse(_ raw: String) -> TimeInterval? {
        let units: [(suffix: String, scale: Double)] = [
            ("ns", 1e-9),
            ("us", 1e-6),
            ("ms", 1e-3),
            ("s", 1),
            ("m", 60),
            ("h", 3600),
            ("d", 86400),
        ]

        var total: TimeInterval = 0
        var number = ""
        var unit = ""
        var matched = false

        func flush() {
            guard !number.isEmpty, !unit.isEmpty, let value = Double(number) else { return }
            // Longest suffix first so "ms" never matches the "s" entry.
            if let match = units.first(where: { $0.suffix == unit }) {
                total += value * match.scale
                matched = true
            }
            number = ""
            unit = ""
        }

        for character in raw.lowercased() {
            if character.isNumber || character == "." {
                if !unit.isEmpty { flush() }
                number.append(character)
            } else if character.isLetter {
                unit.append(character)
            }
        }
        flush()

        return matched ? total : nil
    }
}
