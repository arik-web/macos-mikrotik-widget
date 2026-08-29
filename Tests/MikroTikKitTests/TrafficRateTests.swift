import Foundation
import MikroTikKit

private let start = Date(timeIntervalSince1970: 1_700_000_000)

func runTrafficRateTests() {
    suite("Rate calculation") {
        test("converts a byte delta into bits per second") {
            // Arrange: 250 kB received over 2 seconds = 1 Mbps.
            let previous = CounterSample(rxBytes: 0, txBytes: 0, timestamp: start)
            let current = CounterSample(
                rxBytes: 250_000,
                txBytes: 25_000,
                timestamp: start.addingTimeInterval(2)
            )

            // Act
            let rate = RateCalculator.rate(from: previous, to: current)

            // Assert
            assertEqual(rate.rxBitsPerSecond, 1_000_000, accuracy: 0.001)
            assertEqual(rate.txBitsPerSecond, 100_000, accuracy: 0.001)
            assertEqual(rate.rxMbps, 1.0, accuracy: 1e-9)
            assertEqual(rate.totalBitsPerSecond, 1_100_000, accuracy: 0.001)
        }

        test("a counter reset reports zero instead of a negative spike") {
            let previous = CounterSample(rxBytes: 5_000_000, txBytes: 5_000_000, timestamp: start)
            let current = CounterSample(
                rxBytes: 1_000,
                txBytes: 6_000_000,
                timestamp: start.addingTimeInterval(2)
            )

            let rate = RateCalculator.rate(from: previous, to: current)

            assertEqual(rate.rxBitsPerSecond, 0, accuracy: 1e-9)
            // The direction that kept counting is still reported.
            assertEqual(rate.txBitsPerSecond, 4_000_000, accuracy: 0.001)
        }

        test("ignores samples taken too close together") {
            let previous = CounterSample(rxBytes: 0, txBytes: 0, timestamp: start)
            let current = CounterSample(
                rxBytes: 999_999,
                txBytes: 999_999,
                timestamp: start.addingTimeInterval(0.01)
            )

            assertEqual(RateCalculator.rate(from: previous, to: current), .zero)
        }

        test("ignores out-of-order samples") {
            let previous = CounterSample(rxBytes: 0, txBytes: 0, timestamp: start)
            let current = CounterSample(
                rxBytes: 500_000,
                txBytes: 0,
                timestamp: start.addingTimeInterval(-2)
            )

            assertEqual(RateCalculator.rate(from: previous, to: current), .zero)
        }
    }

    suite("Rate tracker") {
        test("reports zero for the first sample, then real rates") {
            var tracker = RateTracker()

            let first = tracker.update(
                interfaceName: "WAN1",
                sample: CounterSample(rxBytes: 1_000_000, txBytes: 0, timestamp: start)
            )
            let second = tracker.update(
                interfaceName: "WAN1",
                sample: CounterSample(
                    rxBytes: 1_250_000,
                    txBytes: 0,
                    timestamp: start.addingTimeInterval(2)
                )
            )

            assertEqual(first, .zero)
            assertEqual(second.rxBitsPerSecond, 1_000_000, accuracy: 0.001)
        }

        test("keeps interfaces independent") {
            var tracker = RateTracker()
            for name in ["WAN1", "WAN2"] {
                _ = tracker.update(
                    interfaceName: name,
                    sample: CounterSample(rxBytes: 0, txBytes: 0, timestamp: start)
                )
            }

            let cw = tracker.update(
                interfaceName: "WAN1",
                sample: CounterSample(
                    rxBytes: 1_000_000,
                    txBytes: 0,
                    timestamp: start.addingTimeInterval(1)
                )
            )
            let tigo = tracker.update(
                interfaceName: "WAN2",
                sample: CounterSample(
                    rxBytes: 100_000,
                    txBytes: 0,
                    timestamp: start.addingTimeInterval(1)
                )
            )

            assertEqual(cw.rxBitsPerSecond, 8_000_000, accuracy: 0.001)
            assertEqual(tigo.rxBitsPerSecond, 800_000, accuracy: 0.001)
        }

        test("reset clears stored samples") {
            var tracker = RateTracker()
            _ = tracker.update(
                interfaceName: "WAN1",
                sample: CounterSample(rxBytes: 10, txBytes: 10, timestamp: start)
            )
            tracker.reset()

            assertNil(tracker.lastSample(for: "WAN1"))
            let afterReset = tracker.update(
                interfaceName: "WAN1",
                sample: CounterSample(
                    rxBytes: 5_000,
                    txBytes: 5_000,
                    timestamp: start.addingTimeInterval(2)
                )
            )
            assertEqual(afterReset, .zero)
        }
    }
}
