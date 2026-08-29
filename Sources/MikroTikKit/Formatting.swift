import Foundation

/// Locale-independent display helpers. Hand-rolled rather than routed through
/// `ByteCountFormatter` so the output is stable across locales and testable.
public enum Formatting {
    /// Total transferred bytes in binary units, e.g. `1.50 GB`.
    public static func bytes(_ value: UInt64) -> String {
        let units: [(threshold: Double, suffix: String)] = [
            (1024 * 1024 * 1024 * 1024, "TB"),
            (1024 * 1024 * 1024, "GB"),
            (1024 * 1024, "MB"),
            (1024, "KB"),
        ]
        let amount = Double(value)
        for unit in units where amount >= unit.threshold {
            return String(format: "%.2f %@", amount / unit.threshold, unit.suffix)
        }
        return "\(value) B"
    }

    /// Link rate in decimal units, matching how network gear reports speed.
    public static func bitsPerSecond(_ value: Double) -> String {
        let amount = max(value, 0)
        if amount >= 1_000_000_000 {
            return String(format: "%.2f Gbps", amount / 1_000_000_000)
        }
        if amount >= 1_000_000 {
            return String(format: "%.2f Mbps", amount / 1_000_000)
        }
        if amount >= 1_000 {
            return String(format: "%.1f kbps", amount / 1_000)
        }
        return String(format: "%.0f bps", amount)
    }

    /// Compact form for the menu bar, where horizontal space is scarce.
    public static func compactBitsPerSecond(_ value: Double) -> String {
        let amount = max(value, 0)
        if amount >= 1_000_000_000 {
            return String(format: "%.1fG", amount / 1_000_000_000)
        }
        if amount >= 1_000_000 {
            return String(format: "%.1fM", amount / 1_000_000)
        }
        if amount >= 1_000 {
            return String(format: "%.0fk", amount / 1_000)
        }
        return "0"
    }

    public static func latency(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        }
        return String(format: "%.2f s", seconds)
    }

    /// Coarse "how fresh is this" label for the header and the widget footer.
    public static func age(of date: Date, now: Date = Date()) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(Int(seconds))s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        return "\(Int(seconds / 3600))h ago"
    }

    public static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", max(min(fraction, 1), 0) * 100)
    }
}
