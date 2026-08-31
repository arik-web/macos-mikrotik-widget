import Foundation

/// One row of `/ip/firewall/address-list`.
public struct AddressListEntry: Identifiable, Codable, Equatable {
    public let id: String
    public let list: String
    public let address: String
    public let comment: String?
    public let isDynamic: Bool
    public let isDisabled: Bool

    public init(
        id: String,
        list: String,
        address: String,
        comment: String? = nil,
        isDynamic: Bool = false,
        isDisabled: Bool = false
    ) {
        self.id = id
        self.list = list
        self.address = address
        self.comment = comment
        self.isDynamic = isDynamic
        self.isDisabled = isDisabled
    }

    public init?(record: RouterRecord) {
        guard
            let id = record.string(".id"),
            let list = record.string("list"),
            let address = record.string("address")
        else { return nil }
        self.init(
            id: id,
            list: list,
            address: address,
            comment: record.string("comment"),
            isDynamic: record.flag("dynamic"),
            isDisabled: record.flag("disabled")
        )
    }
}

/// Which uplink a client's traffic is pinned to, if any.
public enum RoutePin: Equatable, Hashable {
    /// Not in any lock list: the load balancer decides per connection.
    case loadBalanced
    /// Pinned to one WAN by membership of that WAN's lock list.
    case pinned(String)

    public var label: String {
        switch self {
        case .loadBalanced: return "LB"
        case .pinned(let name): return name
        }
    }

    public var isPinned: Bool { self != .loadBalanced }
}
