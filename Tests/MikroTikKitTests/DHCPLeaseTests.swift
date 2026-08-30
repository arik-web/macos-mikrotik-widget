import Foundation
import MikroTikKit

func runDHCPLeaseTests() {
    suite("DHCP leases") {
        test("parses a reserved lease") {
            let json = #"""
            [{".id":"*1","address":"192.168.88.83","mac-address":"EC:71:DB:80:FA:59",
              "host-name":"admin2","status":"bound","dynamic":"false","disabled":"false",
              "server":"defconf","last-seen":"1m30s"}]
            """#
            let records = try Fixture.records(json)
            let lease = try unwrap(DHCPLease(record: try unwrap(records.first)))

            assertEqual(lease.id, "*1")
            assertEqual(lease.address, "192.168.88.83")
            assertEqual(lease.macAddress, "EC:71:DB:80:FA:59")
            assertEqual(lease.displayName, "admin2")
            assertFalse(lease.isDynamic)
            assertEqual(lease.kindLabel, "Reserved")
            assertTrue(lease.isBound)
        }

        test("parses a dynamic lease with no host name") {
            let json = #"""
            [{".id":"*45","address":"192.168.88.174","mac-address":"FC:A1:83:27:9A:F3",
              "status":"bound","dynamic":"true","disabled":"false"}]
            """#
            let records = try Fixture.records(json)
            let lease = try unwrap(DHCPLease(record: try unwrap(records.first)))

            assertTrue(lease.isDynamic)
            assertEqual(lease.kindLabel, "Dynamic")
            assertEqual(lease.displayName, "unnamed", "a nameless client still needs a label")
            assertFalse(lease.hasName)
        }

        test("an operator comment beats the client's host name") {
            let json = #"""
            [{".id":"*2","address":"192.168.88.10","mac-address":"AA:BB:CC:DD:EE:FF",
              "host-name":"android-9f2c","comment":"Kitchen tablet","dynamic":"false"}]
            """#
            let records = try Fixture.records(json)
            let lease = try unwrap(DHCPLease(record: try unwrap(records.first)))
            assertEqual(lease.displayName, "Kitchen tablet")
        }

        test("a row without an id or address is skipped") {
            let json = #"""
            [{"address":"192.168.88.5"},{".id":"*3"},
             {".id":"*4","address":"192.168.88.6","mac-address":"AA:BB:CC:00:11:22","dynamic":"true"}]
            """#
            let records = try Fixture.records(json)
            let leases = records.compactMap(DHCPLease.init(record:))
            assertEqual(leases.count, 1, "only the complete row survives")
            assertEqual(leases[0].address, "192.168.88.6")
        }

        test("sorts reservations first, then numerically by address") {
            let leases = [
                DHCPLease(id: "*1", address: "192.168.88.100", macAddress: "a", isDynamic: true),
                DHCPLease(id: "*2", address: "192.168.88.9", macAddress: "b", isDynamic: true),
                DHCPLease(id: "*3", address: "192.168.88.50", macAddress: "c", isDynamic: false),
            ].sortedForDisplay()

            assertEqual(leases.map(\.address),
                        ["192.168.88.50", "192.168.88.9", "192.168.88.100"],
                        "reserved first, and .9 sorts before .100")
        }

        test("repairs a host name that is not valid UTF-8") {
            // A real router returned exactly this: a client registered raw
            // Latin-1 bytes as its host-name, and JSONDecoder rejected the
            // entire 77-row lease list over it.
            var bytes = Array(#"[{".id":"*9","address":"192.168.88.7","mac-address":"AA","host-name":""#.utf8)
            bytes += [0xFD, 0xA0, 0xFC]
            bytes += Array(#"","dynamic":"true"}]"#.utf8)
            let raw = Data(bytes)

            assertNil(
                try? JSONDecoder().decode([RouterRecord].self, from: raw),
                "the raw payload must be the thing that fails, or this test proves nothing"
            )

            let repaired = try unwrap(RouterClient.repairingUTF8(raw))
            let records = try JSONDecoder().decode([RouterRecord].self, from: repaired)
            let lease = try unwrap(DHCPLease(record: try unwrap(records.first)))
            assertEqual(lease.address, "192.168.88.7")
            assertTrue(lease.hasName, "the name survives, with the bad bytes replaced")
        }

        test("valid UTF-8 needs no repair") {
            let clean = Data(#"[{".id":"*1","address":"192.168.88.7"}]"#.utf8)
            assertNil(RouterClient.repairingUTF8(clean),
                      "returning nil keeps the common path free of a pointless retry")
        }
    }
}
