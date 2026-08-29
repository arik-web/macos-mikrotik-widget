import Foundation
import MikroTikKit

private let now = Date(timeIntervalSince1970: 1_700_000_000)
private let config = RouterConfig()

func runSnapshotBuilderTests() {
    suite("Snapshot building") {
        test("builds a snapshot from router state") {
            // Arrange
            let rates = [
                "WAN1": TrafficRate(rxBitsPerSecond: 48_000_000, txBitsPerSecond: 6_000_000),
                "WAN2": TrafficRate(rxBitsPerSecond: 1_000_000, txBitsPerSecond: 250_000),
            ]
            let pings = [
                "WAN1": PingOutcome(sent: 3, received: 3, averageLatency: 0.012),
                "WAN2": PingOutcome(sent: 3, received: 0, averageLatency: nil),
            ]

            // Act
            let snapshot = SnapshotBuilder.build(
                config: config,
                state: try Fixture.state(),
                rates: rates,
                pings: pings,
                capturedAt: now
            )

            // Assert
            assertTrue(snapshot.isReachable)
            assertEqual(snapshot.routerHost, "192.168.88.1")
            assertEqual(snapshot.activeWAN, "WAN1")

            let cw = try unwrap(snapshot.interface(named: "WAN1"))
            assertEqual(cw.ipAddress, "192.168.100.2")
            assertEqual(cw.role, .wan)
            assertTrue(cw.isActiveGateway)
            assertEqual(cw.pingStatus, .up)
            assertEqual(cw.rxBitsPerSecond, 48_000_000, accuracy: 1e-9)
            assertTrue(cw.isHealthy)

            let tigo = try unwrap(snapshot.interface(named: "WAN2"))
            assertFalse(tigo.isActiveGateway)
            assertEqual(tigo.pingStatus, .down)
            // The link is up but the internet behind it is not.
            assertTrue(tigo.isUp)
            assertFalse(tigo.isHealthy)
        }

        test("orders WANs first, then LAN, and drops noise interfaces") {
            let snapshot = SnapshotBuilder.build(
                config: config,
                state: try Fixture.state(),
                rates: [:],
                pings: [:],
                capturedAt: now
            )

            assertEqual(snapshot.interfaces.map(\.name), ["WAN1", "WAN2", "bridge1"])
            assertNil(snapshot.interface(named: "lo"), "loopback should not be displayed")
        }

        test("interfaces without a rate report zero and unknown ping") {
            let snapshot = SnapshotBuilder.build(
                config: config,
                state: try Fixture.state(),
                rates: [:],
                pings: [:],
                capturedAt: now
            )

            let cw = try unwrap(snapshot.interface(named: "WAN1"))
            assertEqual(cw.rxBitsPerSecond, 0, accuracy: 1e-9)
            assertEqual(cw.pingStatus, .unknown)
        }

        test("totals cover WAN interfaces only") {
            let snapshot = SnapshotBuilder.build(
                config: config,
                state: try Fixture.state(),
                rates: [:],
                pings: [:],
                capturedAt: now
            )

            // 1_000_000 (WAN1) + 2_000_000 (WAN2); the bridge is excluded.
            assertEqual(snapshot.totalRxBytes, 3_000_000)
            assertEqual(snapshot.totalTxBytes, 1_300_000)
        }
    }

    suite("Active gateway resolution") {
        test("prefers the lowest-distance active default route") {
            let resolved = SnapshotBuilder.activeGatewayInterfaces(
                routes: try Fixture.routes(),
                addresses: try Fixture.addresses(),
                knownInterfaces: ["WAN1", "WAN2", "bridge1"]
            )

            assertEqual(resolved, ["WAN1"])
        }

        test("ignores inactive and disabled default routes") {
            let json = """
            [
              {".id":"*1","dst-address":"0.0.0.0/0","immediate-gw":"192.168.100.1%WAN1","distance":"1",
               "active":"false","disabled":"false"},
              {".id":"*2","dst-address":"0.0.0.0/0","immediate-gw":"192.168.100.129%WAN2","distance":"5",
               "active":"true","disabled":"false"}
            ]
            """

            let resolved = SnapshotBuilder.activeGatewayInterfaces(
                routes: try Fixture.records(json).compactMap(RouterRoute.init(record:)),
                addresses: [],
                knownInterfaces: ["WAN1", "WAN2"]
            )

            assertEqual(resolved, ["WAN2"])
        }

        test("treats an explicit inactive flag as not carrying traffic") {
            let json = """
            [{".id":"*1","dst-address":"0.0.0.0/0","immediate-gw":"192.168.100.1%WAN1","distance":"1",
              "active":"true","inactive":"true","disabled":"false"}]
            """

            let resolved = SnapshotBuilder.activeGatewayInterfaces(
                routes: try Fixture.records(json).compactMap(RouterRoute.init(record:)),
                addresses: [],
                knownInterfaces: ["WAN1"]
            )

            assertTrue(resolved.isEmpty)
        }

        test("does not guess when both WANs share a subnet") {
            // No immediate-gw, and 192.168.100.0/24 is owned by both uplinks.
            let json = """
            [{".id":"*1","dst-address":"0.0.0.0/0","gateway":"192.168.100.1","distance":"1",
              "active":"true","disabled":"false"}]
            """

            let resolved = SnapshotBuilder.activeGatewayInterfaces(
                routes: try Fixture.records(json).compactMap(RouterRoute.init(record:)),
                addresses: try Fixture.addresses(),
                knownInterfaces: ["WAN1", "WAN2", "bridge1"]
            )

            assertTrue(resolved.isEmpty)
        }

        test("falls back to a subnet match when it is unambiguous") {
            let json = """
            [{".id":"*1","dst-address":"0.0.0.0/0","gateway":"192.168.88.254","distance":"1",
              "active":"true","disabled":"false"}]
            """

            let resolved = SnapshotBuilder.activeGatewayInterfaces(
                routes: try Fixture.records(json).compactMap(RouterRoute.init(record:)),
                addresses: try Fixture.addresses(),
                knownInterfaces: ["WAN1", "WAN2", "bridge1"]
            )

            assertEqual(resolved, ["bridge1"])
        }

        test("resolves a gateway given as an interface name") {
            let json = """
            [{".id":"*1","dst-address":"0.0.0.0/0","gateway":"WAN1","distance":"1",
              "active":"true","disabled":"false"}]
            """

            let resolved = SnapshotBuilder.activeGatewayInterfaces(
                routes: try Fixture.records(json).compactMap(RouterRoute.init(record:)),
                addresses: [],
                knownInterfaces: ["WAN1", "WAN2"]
            )

            assertEqual(resolved, ["WAN1"])
        }

        test("resolves to empty when there is no default route") {
            assertTrue(
                SnapshotBuilder.activeGatewayInterfaces(
                    routes: [],
                    addresses: [],
                    knownInterfaces: ["WAN1"]
                ).isEmpty
            )
        }
    }

    suite("Live router fixtures") {
        test("returns both legs of an ECMP default route") {
            let resolved = SnapshotBuilder.activeGatewayInterfaces(
                routes: try Fixture.records(Fixture.liveRoutesJSON)
                    .compactMap(RouterRoute.init(record:)),
                addresses: try Fixture.addresses(),
                knownInterfaces: ["WAN1", "WAN2", "bridge1"]
            )

            assertEqual(resolved, ["WAN1", "WAN2"], "load balanced across both uplinks")
        }

        test("ignores default routes belonging to other routing tables") {
            let routes = try Fixture.records(Fixture.liveRoutesJSON)
                .compactMap(RouterRoute.init(record:))

            // The `tigo` table also has a usable distance-1 default route; only
            // the `main` table decides where ordinary LAN traffic goes.
            let usableMain = routes.filter { $0.isDefaultRoute && $0.isUsable && $0.isMainTable }
            assertEqual(usableMain.count, 1)
            assertEqual(usableMain[0].routingTable, "main")
            assertTrue(usableMain[0].isECMP)
        }

        test("hides bridge members and loopback, keeps addressed interfaces") {
            let snapshot = SnapshotBuilder.build(
                config: config,
                state: try Fixture.liveState(),
                rates: [:],
                pings: [:],
                capturedAt: now
            )

            assertEqual(snapshot.interfaces.map(\.name), ["WAN1", "WAN2", "bridge1"])
            assertEqual(snapshot.activeRouteLabel, "WAN1 + WAN2")
        }

        test("shows every interface when the operator asks for it") {
            var verbose = config
            verbose.showAllInterfaces = true

            let snapshot = SnapshotBuilder.build(
                config: verbose,
                state: try Fixture.liveState(),
                rates: [:],
                pings: [:],
                capturedAt: now
            )

            assertEqual(snapshot.interfaces.count, 6, "everything except loopback")
            assertNil(snapshot.interface(named: "lo"))
            assertEqual(snapshot.interfaces.map(\.name).prefix(3).map { $0 }, ["WAN1", "WAN2", "bridge1"])
        }

        test("marks every ECMP leg as an active gateway") {
            let snapshot = SnapshotBuilder.build(
                config: config,
                state: try Fixture.liveState(),
                rates: [:],
                pings: [:],
                capturedAt: now
            )

            assertTrue(try unwrap(snapshot.interface(named: "WAN1")).isActiveGateway)
            assertTrue(try unwrap(snapshot.interface(named: "WAN2")).isActiveGateway)
            assertFalse(try unwrap(snapshot.interface(named: "bridge1")).isActiveGateway)
        }
    }

    suite("IPv4") {
        test("tests CIDR membership") {
            assertTrue(IPv4.cidr("192.168.100.2/24", contains: "192.168.100.131"))
            assertFalse(IPv4.cidr("192.168.100.2/24", contains: "192.168.101.1"))
            assertTrue(IPv4.cidr("192.168.88.1/8", contains: "192.1.2.3"))
            assertTrue(IPv4.cidr("192.168.88.1/32", contains: "192.168.88.1"))
            assertFalse(IPv4.cidr("192.168.88.1/32", contains: "192.168.88.2"))
            assertTrue(IPv4.cidr("0.0.0.0/0", contains: "8.8.8.8"))
        }

        test("rejects malformed addresses") {
            assertNil(IPv4.parse("999.1.1.1"))
            assertNil(IPv4.parse("10.0.0"))
            assertNil(IPv4.parse("not-an-ip"))
            assertFalse(IPv4.cidr("garbage/24", contains: "192.168.88.1"))
            assertEqual(IPv4.parse("255.255.255.255"), UInt32.max)
            assertEqual(IPv4.parse("0.0.0.0"), 0)
        }
    }

    suite("Snapshot helpers") {
        test("primary WAN prefers the active gateway, then the busiest link") {
            let snapshot = DashboardSnapshot.placeholder(now: now)
            assertEqual(snapshot.primaryWAN?.name, "WAN1")

            let noActive = DashboardSnapshot(
                capturedAt: now,
                routerHost: "192.168.88.1",
                isReachable: true,
                interfaces: snapshot.interfaces.map { interface in
                    InterfaceSnapshot(
                        name: interface.name,
                        ipAddress: interface.ipAddress,
                        isRunning: interface.isRunning,
                        isDisabled: interface.isDisabled,
                        rxBytes: interface.rxBytes,
                        txBytes: interface.txBytes,
                        rxBitsPerSecond: interface.name == "WAN2" ? 90_000_000 : 1_000,
                        txBitsPerSecond: 0,
                        role: interface.role,
                        isActiveGateway: false,
                        pingStatus: interface.pingStatus,
                        pingLatency: interface.pingLatency
                    )
                },
                activeWANs: []
            )

            assertEqual(noActive.primaryWAN?.name, "WAN2")
        }

        test("honours the staleness window") {
            let snapshot = DashboardSnapshot.placeholder(now: now)

            assertFalse(snapshot.isStale(now: now.addingTimeInterval(60), tolerance: 240))
            assertTrue(snapshot.isStale(now: now.addingTimeInterval(600), tolerance: 240))
        }

        test("survives a JSON round trip") {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let original = DashboardSnapshot.placeholder(now: now)
            let restored = try decoder.decode(
                DashboardSnapshot.self,
                from: encoder.encode(original)
            )

            assertEqual(original, restored)
        }

        test("offline snapshot carries the error and no interfaces") {
            let snapshot = DashboardSnapshot.offline(host: "192.168.88.1", message: "boom", now: now)

            assertFalse(snapshot.isReachable)
            assertEqual(snapshot.errorMessage, "boom")
            assertTrue(snapshot.interfaces.isEmpty)
            assertNil(snapshot.primaryWAN)
        }
    }

    suite("Configuration") {
        test("assigns roles and display order") {
            assertEqual(config.role(for: "WAN1"), .wan)
            assertEqual(config.role(for: "bridge1"), .lan)
            assertEqual(config.role(for: "ether7"), .other)

            assertLessThan(config.displayOrder(for: "WAN1"), config.displayOrder(for: "WAN2"))
            assertLessThan(config.displayOrder(for: "WAN2"), config.displayOrder(for: "bridge1"))
            assertLessThan(config.displayOrder(for: "bridge1"), config.displayOrder(for: "ether7"))
        }

        test("base URL follows the TLS setting") {
            assertEqual(
                RouterConfig(host: "192.168.88.1").baseURL?.absoluteString,
                "http://192.168.88.1/rest"
            )

            var secure = RouterConfig(host: "router.local")
            secure.useTLS = true
            assertEqual(secure.baseURL?.absoluteString, "https://router.local/rest")
        }
    }
}
