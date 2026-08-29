import Foundation
import MikroTikKit

enum Fixture {
    /// Decodes a RouterOS-style JSON array into records.
    static func records(_ json: String) throws -> [RouterRecord] {
        try JSONDecoder().decode([RouterRecord].self, from: Data(json.utf8))
    }

    static func record(_ json: String) throws -> RouterRecord {
        try JSONDecoder().decode(RouterRecord.self, from: Data(json.utf8))
    }

    /// Two WAN uplinks plus the LAN bridge, shaped like the real router.
    static let interfacesJSON = """
    [
      {".id":"*1","name":"WAN1","type":"ether","running":"true","disabled":"false",
       "rx-byte":"1000000","tx-byte":"500000","mac-address":"AA:BB:CC:00:00:01"},
      {".id":"*2","name":"WAN2","type":"ether","running":"true","disabled":"false",
       "rx-byte":"2000000","tx-byte":"800000","mac-address":"AA:BB:CC:00:00:02"},
      {".id":"*3","name":"bridge1","type":"bridge","running":"true","disabled":"false",
       "rx-byte":"9000000","tx-byte":"9500000"},
      {".id":"*4","name":"lo","type":"loopback","running":"true","disabled":"false",
       "rx-byte":"0","tx-byte":"0"}
    ]
    """

    static let addressesJSON = """
    [
      {".id":"*1","address":"192.168.100.2/24","network":"192.168.100.0","interface":"WAN1",
       "actual-interface":"WAN1","disabled":"false","dynamic":"false"},
      {".id":"*2","address":"192.168.100.131/24","network":"192.168.100.0","interface":"WAN2",
       "actual-interface":"WAN2","disabled":"false","dynamic":"false"},
      {".id":"*3","address":"192.168.88.1/24","network":"192.168.88.0","interface":"bridge1",
       "actual-interface":"bridge1","disabled":"false","dynamic":"false"}
    ]
    """

    static let routesJSON = """
    [
      {".id":"*1","dst-address":"0.0.0.0/0","gateway":"192.168.100.1","immediate-gw":"192.168.100.1%WAN1",
       "distance":"1","active":"true","disabled":"false","routing-table":"main","check-gateway":"ping"},
      {".id":"*2","dst-address":"0.0.0.0/0","gateway":"192.168.100.129","immediate-gw":"192.168.100.129%WAN2",
       "distance":"2","active":"true","disabled":"false","routing-table":"main","check-gateway":"ping"},
      {".id":"*3","dst-address":"192.168.88.0/24","gateway":"bridge1","distance":"0","active":"true","disabled":"false"}
    ]
    """

    /// Captured verbatim from the router at 192.168.88.1 (RouterOS 7 with
    /// policy-routing load balancing). Exercises the shapes that differ from
    /// the simple case: ECMP `immediate-gw` lists, per-WAN routing tables and
    /// `inactive` in place of a missing `active`.
    static let liveRoutesJSON = """
    [
      {".id":"*8000001B","check-gateway":"ping","comment":"LB main WAN1","distance":"1",
       "dst-address":"0.0.0.0/0","dynamic":"false","gateway":"8.8.4.4","immediate-gw":"",
       "inactive":"true","routing-table":"main","static":"true"},
      {".id":"*8000001C","active":"true","check-gateway":"ping","comment":"LB main WAN2","distance":"2",
       "dst-address":"0.0.0.0/0","dynamic":"false","ecmp":"true","gateway":"1.0.0.1",
       "immediate-gw":"192.168.100.254%WAN1,192.168.100.254%WAN2","inactive":"false",
       "routing-table":"main","static":"true"},
      {".id":"*8000001F","active":"true","check-gateway":"ping","comment":"LB tigo primary","distance":"1",
       "dst-address":"0.0.0.0/0","dynamic":"false","ecmp":"true","gateway":"1.0.0.1",
       "immediate-gw":"192.168.100.254%WAN1,192.168.100.254%WAN2","inactive":"false",
       "routing-table":"tigo","static":"true"},
      {".id":"*8000001D","check-gateway":"ping","comment":"LB cw primary","distance":"1",
       "dst-address":"0.0.0.0/0","dynamic":"false","gateway":"8.8.4.4","immediate-gw":"",
       "inactive":"true","routing-table":"cw","static":"true"}
    ]
    """

    /// The real interface list: two WANs, six bridge member ports, an empty
    /// SFP cage, the bridge itself and loopback.
    static let liveInterfacesJSON = """
    [
      {".id":"*2","name":"WAN1","type":"ether","running":"true","disabled":"false",
       "rx-byte":"82865842","tx-byte":"126545076"},
      {".id":"*3","name":"WAN2","type":"ether","running":"true","disabled":"false",
       "rx-byte":"760847150783","tx-byte":"253066573450"},
      {".id":"*4","name":"ether3","type":"ether","running":"false","disabled":"false",
       "rx-byte":"0","tx-byte":"0"},
      {".id":"*5","name":"ether4","type":"ether","running":"true","disabled":"false",
       "rx-byte":"5195733769","tx-byte":"51313388546"},
      {".id":"*9","name":"sfp-sfpplus1","type":"ether","running":"false","disabled":"false",
       "rx-byte":"0","tx-byte":"0"},
      {".id":"*A","name":"bridge1","type":"bridge","running":"true","disabled":"false",
       "rx-byte":"257061392059","tx-byte":"755936152158"},
      {".id":"*B","name":"lo","type":"loopback","running":"true","disabled":"false",
       "rx-byte":"13473216","tx-byte":"13473216"}
    ]
    """

    static func interfaces() throws -> [RouterInterface] {
        try records(interfacesJSON).compactMap(RouterInterface.init(record:))
    }

    static func addresses() throws -> [RouterAddress] {
        try records(addressesJSON).compactMap(RouterAddress.init(record:))
    }

    static func routes() throws -> [RouterRoute] {
        try records(routesJSON).compactMap(RouterRoute.init(record:))
    }

    static func state() throws -> RouterState {
        RouterState(
            interfaces: try interfaces(),
            addresses: try addresses(),
            routes: try routes()
        )
    }

    static func liveState() throws -> RouterState {
        RouterState(
            interfaces: try records(liveInterfacesJSON).compactMap(RouterInterface.init(record:)),
            addresses: try addresses(),
            routes: try records(liveRoutesJSON).compactMap(RouterRoute.init(record:))
        )
    }
}
