import Foundation

/// A byte-counter reading taken at a point in time.
public struct CounterSample: Equatable {
    public let rxBytes: UInt64
    public let txBytes: UInt64
    public let timestamp: Date

    public init(rxBytes: UInt64, txBytes: UInt64, timestamp: Date) {
        self.rxBytes = rxBytes
        self.txBytes = txBytes
        self.timestamp = timestamp
    }
}

public struct TrafficRate: Equatable, Codable {
    public let rxBitsPerSecond: Double
    public let txBitsPerSecond: Double

    public init(rxBitsPerSecond: Double, txBitsPerSecond: Double) {
        self.rxBitsPerSecond = rxBitsPerSecond
        self.txBitsPerSecond = txBitsPerSecond
    }

    public static let zero = TrafficRate(rxBitsPerSecond: 0, txBitsPerSecond: 0)

    public var rxMbps: Double { rxBitsPerSecond / 1_000_000 }
    public var txMbps: Double { txBitsPerSecond / 1_000_000 }
    public var totalBitsPerSecond: Double { rxBitsPerSecond + txBitsPerSecond }
}

public enum RateCalculator {
    /// Samples closer together than this are treated as duplicates; dividing by
    /// a near-zero interval produces meaningless spikes.
    static let minimumInterval: TimeInterval = 0.05

    /// Converts two counter readings into a bits-per-second rate.
    ///
    /// A counter that moves backwards means the interface or the router reset
    /// its statistics, so that direction reports zero rather than a spike.
    public static func rate(from previous: CounterSample, to current: CounterSample) -> TrafficRate {
        let interval = current.timestamp.timeIntervalSince(previous.timestamp)
        guard interval >= minimumInterval else { return .zero }

        func bitsPerSecond(_ old: UInt64, _ new: UInt64) -> Double {
            guard new >= old else { return 0 }
            return Double(new - old) * 8 / interval
        }

        return TrafficRate(
            rxBitsPerSecond: bitsPerSecond(previous.rxBytes, current.rxBytes),
            txBitsPerSecond: bitsPerSecond(previous.txBytes, current.txBytes)
        )
    }
}

/// Keeps the most recent counter reading per interface and turns each new poll
/// into a rate. Not thread-safe on its own; the dashboard confines it to the
/// main actor and the widget uses it from a single task.
public struct RateTracker {
    private var samples: [String: CounterSample] = [:]

    public init() {}

    /// Records `sample` for `interfaceName` and returns the rate since the
    /// previous reading, or `.zero` on the very first one.
    public mutating func update(interfaceName: String, sample: CounterSample) -> TrafficRate {
        defer { samples[interfaceName] = sample }
        guard let previous = samples[interfaceName] else { return .zero }
        return RateCalculator.rate(from: previous, to: sample)
    }

    public func lastSample(for interfaceName: String) -> CounterSample? {
        samples[interfaceName]
    }

    public mutating func reset() {
        samples.removeAll()
    }
}
