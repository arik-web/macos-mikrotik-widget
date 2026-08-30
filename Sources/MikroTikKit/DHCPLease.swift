import Foundation

/// One row from `/ip/dhcp-server/lease`.
public struct DHCPLease: Identifiable, Codable, Equatable {
    /// RouterOS item id, e.g. `*45`. Writes address the lease through this.
    public let id: String
    public let address: String
    public let macAddress: String
    public let hostName: String?
    public let comment: String?
    /// `bound`, `waiting`, `offered`… as RouterOS reports it.
    public let status: String?
    /// False for a reservation the operator made, true for one the server
    /// handed out on its own.
    public let isDynamic: Bool
    public let isDisabled: Bool
    public let server: String?
    public let lastSeen: String?
    public let expiresAfter: String?
    public let activeAddress: String?

    public init(
        id: String,
        address: String,
        macAddress: String,
        hostName: String? = nil,
        comment: String? = nil,
        status: String? = nil,
        isDynamic: Bool,
        isDisabled: Bool = false,
        server: String? = nil,
        lastSeen: String? = nil,
        expiresAfter: String? = nil,
        activeAddress: String? = nil
    ) {
        self.id = id
        self.address = address
        self.macAddress = macAddress
        self.hostName = hostName
        self.comment = comment
        self.status = status
        self.isDynamic = isDynamic
        self.isDisabled = isDisabled
        self.server = server
        self.lastSeen = lastSeen
        self.expiresAfter = expiresAfter
        self.activeAddress = activeAddress
    }

    public init?(record: RouterRecord) {
        guard
            let id = record.string(".id"),
            let address = record.string("address")
        else { return nil }
        self.init(
            id: id,
            address: address,
            macAddress: record.string("mac-address") ?? "",
            hostName: record.string("host-name"),
            comment: record.string("comment"),
            status: record.string("status"),
            isDynamic: record.flag("dynamic"),
            isDisabled: record.flag("disabled"),
            server: record.string("server"),
            lastSeen: record.string("last-seen"),
            expiresAfter: record.string("expires-after"),
            activeAddress: record.string("active-address")
        )
    }

    /// What to show as the device's name. RouterOS leaves `host-name` empty for
    /// clients that never sent one, and an operator comment is a better label
    /// than a MAC address when it exists.
    public var displayName: String {
        if let comment, !comment.isEmpty { return comment }
        if let hostName, !hostName.isEmpty { return hostName }
        return "unnamed"
    }

    public var hasName: Bool {
        !(comment?.isEmpty ?? true) || !(hostName?.isEmpty ?? true)
    }

    /// True while the client currently holds the lease.
    public var isBound: Bool { status?.lowercased() == "bound" }

    public var kindLabel: String { isDynamic ? "Dynamic" : "Reserved" }

    /// Sort key: numeric by final octet within the same /24 so 10.0.0.9 comes
    /// before 10.0.0.100, falling back to string order across subnets.
    public var sortKey: (UInt32, String) {
        (IPv4.parse(address) ?? .max, address)
    }
}

public extension Array where Element == DHCPLease {
    /// Reserved first, then by address. Reservations are the rows an operator
    /// curates, so they belong at the top.
    func sortedForDisplay() -> [DHCPLease] {
        sorted { lhs, rhs in
            if lhs.isDynamic != rhs.isDynamic { return !lhs.isDynamic }
            return lhs.sortKey < rhs.sortKey
        }
    }
}
