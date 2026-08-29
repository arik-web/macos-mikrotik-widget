import Foundation
import MikroTikKit

func runFormattingTests() {
    suite("Formatting") {
        test("byte totals use binary units") {
            assertEqual(Formatting.bytes(0), "0 B")
            assertEqual(Formatting.bytes(512), "512 B")
            assertEqual(Formatting.bytes(1536), "1.50 KB")
            assertEqual(Formatting.bytes(5 * 1024 * 1024), "5.00 MB")
            assertEqual(Formatting.bytes(3 * 1024 * 1024 * 1024), "3.00 GB")
            assertEqual(Formatting.bytes(2 * 1024 * 1024 * 1024 * 1024), "2.00 TB")
        }

        test("rates use decimal network units") {
            assertEqual(Formatting.bitsPerSecond(0), "0 bps")
            assertEqual(Formatting.bitsPerSecond(999), "999 bps")
            assertEqual(Formatting.bitsPerSecond(2_500), "2.5 kbps")
            assertEqual(Formatting.bitsPerSecond(12_300_000), "12.30 Mbps")
            assertEqual(Formatting.bitsPerSecond(2_400_000_000), "2.40 Gbps")
        }

        test("negative rates clamp to zero") {
            assertEqual(Formatting.bitsPerSecond(-5), "0 bps")
            assertEqual(Formatting.compactBitsPerSecond(-5), "0")
        }

        test("compact rates fit the menu bar") {
            assertEqual(Formatting.compactBitsPerSecond(0), "0")
            assertEqual(Formatting.compactBitsPerSecond(45_000), "45k")
            assertEqual(Formatting.compactBitsPerSecond(12_300_000), "12.3M")
            assertEqual(Formatting.compactBitsPerSecond(1_500_000_000), "1.5G")
        }

        test("latency renders in milliseconds below a second") {
            assertEqual(Formatting.latency(nil), "—")
            assertEqual(Formatting.latency(0.012), "12 ms")
            assertEqual(Formatting.latency(1.5), "1.50 s")
        }

        test("age is relative and never negative") {
            let now = Date(timeIntervalSince1970: 1_700_000_000)

            assertEqual(Formatting.age(of: now, now: now), "just now")
            assertEqual(Formatting.age(of: now.addingTimeInterval(-30), now: now), "30s ago")
            assertEqual(Formatting.age(of: now.addingTimeInterval(-300), now: now), "5m ago")
            assertEqual(Formatting.age(of: now.addingTimeInterval(-7200), now: now), "2h ago")
            // Clock skew must not produce a negative age.
            assertEqual(Formatting.age(of: now.addingTimeInterval(60), now: now), "just now")
        }

        test("percent is clamped to 0-100") {
            assertEqual(Formatting.percent(0), "0%")
            assertEqual(Formatting.percent(0.335), "34%")
            assertEqual(Formatting.percent(1.4), "100%")
            assertEqual(Formatting.percent(-1), "0%")
        }
    }
}
