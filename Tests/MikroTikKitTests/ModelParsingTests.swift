import Foundation
import MikroTikKit

func runModelParsingTests() {
    suite("Interface and address parsing") {
        test("parses interface rows") {
            let interfaces = try Fixture.interfaces()

            assertEqual(interfaces.count, 4)
            let cw = try unwrap(interfaces.first { $0.name == "WAN1" }, "WAN1 interface")
            assertEqual(cw.id, "*1")
            assertEqual(cw.rxBytes, 1_000_000)
            assertEqual(cw.txBytes, 500_000)
            assertTrue(cw.isRunning)
            assertFalse(cw.isDisabled)
        }

        test("rejects an interface row with no name") {
            let record = try Fixture.record(#"{".id":"*9","type":"ether"}"#)
            assertNil(RouterInterface(record: record))
        }

        test("defaults missing counters to zero") {
            let record = try Fixture.record(#"{".id":"*9","name":"ether5","type":"ether"}"#)
            let interface = try unwrap(RouterInterface(record: record))

            assertEqual(interface.rxBytes, 0)
            assertEqual(interface.txBytes, 0)
            assertFalse(interface.isRunning)
        }

        test("splits an address into IP and prefix") {
            let cw = try unwrap(
                Fixture.addresses().first { $0.interfaceName == "WAN1" },
                "WAN1 address"
            )

            assertEqual(cw.ipOnly, "192.168.100.2")
            assertEqual(cw.prefixLength, 24)
        }

        test("prefers actual-interface over interface") {
            let record = try Fixture.record(
                #"{".id":"*1","address":"192.168.88.5/24","interface":"bridge1","actual-interface":"ether3"}"#
            )
            let address = try unwrap(RouterAddress(record: record))

            assertEqual(address.interfaceName, "ether3")
        }
    }

    suite("Route parsing") {
        test("identifies default routes and their interfaces") {
            let defaults = try Fixture.routes().filter(\.isDefaultRoute)

            assertEqual(defaults.count, 2)
            assertEqual(defaults[0].resolvedInterfaceName, "WAN1")
            assertEqual(defaults[0].gatewayAddress, "192.168.100.1")
            assertEqual(defaults[0].distance, 1)
            assertEqual(defaults[1].resolvedInterfaceName, "WAN2")
        }

        test("falls back to the gateway suffix when immediate-gw is absent") {
            let record = try Fixture.record(
                #"{".id":"*1","dst-address":"0.0.0.0/0","gateway":"192.168.100.1%WAN1","active":"true"}"#
            )
            let route = try unwrap(RouterRoute(record: record))

            assertEqual(route.resolvedInterfaceName, "WAN1")
            assertEqual(route.gatewayAddress, "192.168.100.1")
        }

        test("resolves to nil when no interface suffix is present") {
            let record = try Fixture.record(
                #"{".id":"*1","dst-address":"0.0.0.0/0","gateway":"192.168.100.1"}"#
            )
            let route = try unwrap(RouterRoute(record: record))

            assertNil(route.resolvedInterfaceName)
            assertTrue(route.resolvedInterfaceNames.isEmpty)
        }

        test("splits a comma-separated ECMP immediate-gw into every leg") {
            let json = """
            {".id":"*1","dst-address":"0.0.0.0/0","gateway":"1.0.0.1","active":"true",
             "immediate-gw":"192.168.100.254%WAN1,192.168.100.254%WAN2","ecmp":"true"}
            """
            let route = try unwrap(RouterRoute(record: try Fixture.record(json)))

            assertEqual(route.resolvedInterfaceNames, ["WAN1", "WAN2"])
            assertEqual(route.resolvedInterfaceName, "WAN1")
            assertTrue(route.isECMP)
            // The gateway is a recursive next hop, not an on-link address.
            assertEqual(route.gatewayAddress, "1.0.0.1")
        }

        test("deduplicates repeated legs in an immediate-gw list") {
            let record = try Fixture.record(
                #"{".id":"*1","dst-address":"0.0.0.0/0","immediate-gw":"192.168.88.1%WAN2,192.168.88.2%WAN2"}"#
            )
            let route = try unwrap(RouterRoute(record: record))

            assertEqual(route.resolvedInterfaceNames, ["WAN2"])
        }

        test("an empty immediate-gw does not mask the gateway fallback") {
            let record = try Fixture.record(
                #"{".id":"*1","dst-address":"0.0.0.0/0","immediate-gw":"","gateway":"192.168.100.1%WAN1"}"#
            )
            let route = try unwrap(RouterRoute(record: record))

            assertEqual(route.resolvedInterfaceNames, ["WAN1"])
        }

        test("reads routing table and usability flags") {
            let routes = try Fixture.records(Fixture.liveRoutesJSON)
                .compactMap(RouterRoute.init(record:))

            let inactiveMain = try unwrap(routes.first { $0.id == "*8000001B" })
            assertFalse(inactiveMain.isUsable, "inactive=true means it carries nothing")
            assertTrue(inactiveMain.isMainTable)

            let activeMain = try unwrap(routes.first { $0.id == "*8000001C" })
            assertTrue(activeMain.isUsable)
            assertTrue(activeMain.isMainTable)

            let tigoTable = try unwrap(routes.first { $0.id == "*8000001F" })
            assertTrue(tigoTable.isUsable)
            assertFalse(tigoTable.isMainTable, "belongs to the tigo policy table")
        }

        test("a route with no routing-table key belongs to main") {
            let record = try Fixture.record(#"{".id":"*1","dst-address":"0.0.0.0/0"}"#)
            let route = try unwrap(RouterRoute(record: record))

            assertTrue(route.isMainTable)
        }
    }

    suite("Duration parsing") {
        test("parses RouterOS duration strings") {
            assertEqual(RouterDuration.parse("12ms") ?? 0, 0.012, accuracy: 1e-9)
            assertEqual(RouterDuration.parse("450us") ?? 0, 0.00045, accuracy: 1e-9)
            assertEqual(RouterDuration.parse("1s200ms") ?? 0, 1.2, accuracy: 1e-9)
            assertEqual(RouterDuration.parse("2m30s") ?? 0, 150, accuracy: 1e-9)
        }

        test("returns nil for unparseable input") {
            assertNil(RouterDuration.parse(""))
            assertNil(RouterDuration.parse("timeout"))
            assertNil(RouterDuration.parse("123"))
        }
    }

    suite("Ping aggregation") {
        test("uses the cumulative counters from the last reply") {
            let json = """
            [
              {"seq":"0","host":"8.8.8.8","time":"10ms","sent":"1","received":"1","packet-loss":"0"},
              {"seq":"1","host":"8.8.8.8","time":"20ms","sent":"2","received":"2","packet-loss":"0"},
              {"seq":"2","host":"8.8.8.8","time":"30ms","sent":"3","received":"3","packet-loss":"0"}
            ]
            """

            let outcome = PingOutcome.aggregate(records: try Fixture.records(json))

            assertEqual(outcome.sent, 3)
            assertEqual(outcome.received, 3)
            assertEqual(outcome.averageLatency ?? 0, 0.020, accuracy: 1e-9)
            assertTrue(outcome.isReachable)
            assertEqual(outcome.status, .up)
            assertEqual(outcome.packetLoss, 0, accuracy: 1e-9)
        }

        test("reports a fully timed-out ping as down") {
            let json = """
            [
              {"seq":"0","host":"8.8.8.8","status":"timeout","sent":"1","received":"0"},
              {"seq":"1","host":"8.8.8.8","status":"timeout","sent":"2","received":"0"}
            ]
            """

            let outcome = PingOutcome.aggregate(records: try Fixture.records(json))

            assertEqual(outcome.sent, 2)
            assertEqual(outcome.received, 0)
            assertNil(outcome.averageLatency)
            assertEqual(outcome.status, .down)
            assertEqual(outcome.packetLoss, 1, accuracy: 1e-9)
        }

        test("computes partial packet loss") {
            let json = """
            [
              {"seq":"0","time":"10ms","sent":"1","received":"1"},
              {"seq":"1","status":"timeout","sent":"2","received":"1"},
              {"seq":"2","time":"30ms","sent":"3","received":"2"}
            ]
            """

            let outcome = PingOutcome.aggregate(records: try Fixture.records(json))

            assertEqual(outcome.received, 2)
            assertEqual(outcome.packetLoss, 1.0 / 3.0, accuracy: 1e-9)
            assertEqual(outcome.averageLatency ?? 0, 0.020, accuracy: 1e-9)
        }

        test("treats an empty response as unreachable") {
            assertEqual(PingOutcome.aggregate(records: []), .unreachable)
            assertFalse(PingOutcome.unreachable.isReachable)
            assertEqual(PingOutcome.unreachable.packetLoss, 1, accuracy: 1e-9)
        }

        test("does not time an unreachable reply as latency") {
            // Captured from the router: an ICMP "host unreachable" answer is
            // timed like a real reply, but nothing actually got through.
            let json = """
            [
              {"host":"192.168.100.2","packet-loss":"100","received":"0","sent":"1","seq":"0",
               "status":"host unreachable","time":"614ms933us","ttl":"64"},
              {"host":"8.8.8.8","packet-loss":"100","received":"0","sent":"2","seq":"1","status":"timeout"},
              {"host":"8.8.8.8","packet-loss":"100","received":"0","sent":"3","seq":"2","status":"timeout"}
            ]
            """

            let outcome = PingOutcome.aggregate(records: try Fixture.records(json))

            assertEqual(outcome.sent, 3)
            assertEqual(outcome.received, 0)
            assertEqual(outcome.status, .down)
            assertNil(outcome.averageLatency, "615 ms of unreachability is not latency")
        }

        test("prefers the router's own avg-rtt summary") {
            let json = """
            [
              {"host":"8.8.8.8","sent":"1","received":"1","seq":"0","time":"56ms639us","ttl":"112"},
              {"avg-rtt":"57ms51us","host":"8.8.8.8","max-rtt":"57ms464us","min-rtt":"56ms639us",
               "packet-loss":"0","received":"2","sent":"2","seq":"1","time":"57ms464us","ttl":"112"}
            ]
            """

            let outcome = PingOutcome.aggregate(records: try Fixture.records(json))

            assertEqual(outcome.sent, 2)
            assertEqual(outcome.received, 2)
            assertEqual(outcome.status, .up)
            assertEqual(outcome.averageLatency ?? 0, 0.057051, accuracy: 1e-9)
        }

        test("counts records when cumulative counters are absent") {
            let json = #"[{"seq":"0","time":"10ms"},{"seq":"1","time":"12ms"}]"#

            let outcome = PingOutcome.aggregate(records: try Fixture.records(json))

            assertEqual(outcome.sent, 2)
            assertEqual(outcome.received, 2)
        }
    }
}
