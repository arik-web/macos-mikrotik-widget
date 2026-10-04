import Foundation

/// Decides whether the router counts as unreachable, and whether what is on
/// screen is stale.
///
/// Pure on purpose: this only matters when things are broken, which is exactly
/// when it is hardest to exercise by hand, so it lives here rather than in the
/// view model where no test can reach it.
public struct ReachabilityState: Equatable {
    /// Failed polls in a row before the UI shouts. At a 2-second poll, two
    /// misses is ~4s of silence — enough to ride out one dropped request
    /// without the banner flapping on and off.
    public static let failureThreshold = 2

    public let consecutiveFailures: Int
    public let lastUpdate: Date?
    public let hasInterfaces: Bool

    public init(consecutiveFailures: Int, lastUpdate: Date?, hasInterfaces: Bool) {
        self.consecutiveFailures = consecutiveFailures
        self.lastUpdate = lastUpdate
        self.hasInterfaces = hasInterfaces
    }

    public var isUnreachable: Bool {
        consecutiveFailures >= Self.failureThreshold
    }

    /// Seconds since the last good reading, or nil when it is still answering
    /// or has never answered at all.
    public func silentFor(now: Date = Date()) -> TimeInterval? {
        guard isUnreachable, let lastUpdate else { return nil }
        return now.timeIntervalSince(lastUpdate)
    }

    /// Numbers are on screen but no longer current. A router that never
    /// answered shows an empty state instead, which is already honest.
    public var isShowingStaleData: Bool { isUnreachable && hasInterfaces }
}
