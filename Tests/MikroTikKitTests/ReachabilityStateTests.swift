import Foundation
import MikroTikKit

func runReachabilityTests() {
    suite("Reachability") {
        let now = Date()

        test("a single failed poll does not cry wolf") {
            // One dropped request on a 2s poll is normal; the banner must not
            // flap on and off every time a packet is lost.
            let s = ReachabilityState(consecutiveFailures: 1, lastUpdate: now, hasInterfaces: true)
            assertFalse(s.isUnreachable)
            assertNil(s.silentFor(now: now))
            assertFalse(s.isShowingStaleData)
        }

        test("two failures in a row is an outage") {
            let s = ReachabilityState(consecutiveFailures: 2, lastUpdate: now, hasInterfaces: true)
            assertTrue(s.isUnreachable)
            assertTrue(s.isShowingStaleData, "numbers are on screen and no longer current")
        }

        test("reports how long it has been silent") {
            let s = ReachabilityState(
                consecutiveFailures: 5,
                lastUpdate: now.addingTimeInterval(-42),
                hasInterfaces: true
            )
            let silent = try unwrap(s.silentFor(now: now))
            assertEqual(Int(silent.rounded()), 42)
        }

        test("a router that never answered is not 'stale', it is empty") {
            // Dimming an empty card and labelling it LAST KNOWN would be a lie.
            let s = ReachabilityState(consecutiveFailures: 9, lastUpdate: nil, hasInterfaces: false)
            assertTrue(s.isUnreachable)
            assertFalse(s.isShowingStaleData)
            assertNil(s.silentFor(now: now), "no last-good reading to measure from")
        }

        test("recovery clears the state") {
            let s = ReachabilityState(consecutiveFailures: 0, lastUpdate: now, hasInterfaces: true)
            assertFalse(s.isUnreachable)
            assertFalse(s.isShowingStaleData)
            assertNil(s.silentFor(now: now))
        }

        test("the threshold is what the UI documents") {
            assertEqual(ReachabilityState.failureThreshold, 2)
        }
    }
}
