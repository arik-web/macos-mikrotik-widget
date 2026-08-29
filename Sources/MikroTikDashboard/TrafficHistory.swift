import Foundation
import MikroTikKit

/// A bounded ring of recent rates, used to draw the per-interface sparkline.
struct TrafficHistory: Equatable {
    /// 60 samples at the default 2-second poll is two minutes of history.
    static let capacity = 60

    private(set) var rx: [Double] = []
    private(set) var tx: [Double] = []

    mutating func append(_ rate: TrafficRate) {
        rx.append(rate.rxBitsPerSecond)
        tx.append(rate.txBitsPerSecond)
        if rx.count > Self.capacity { rx.removeFirst(rx.count - Self.capacity) }
        if tx.count > Self.capacity { tx.removeFirst(tx.count - Self.capacity) }
    }

    var peak: Double {
        max(rx.max() ?? 0, tx.max() ?? 0)
    }

    var isEmpty: Bool { rx.isEmpty && tx.isEmpty }
}
