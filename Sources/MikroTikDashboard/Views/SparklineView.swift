import SwiftUI

/// Two-series area sparkline (download over upload), drawn without any
/// charting dependency.
struct SparklineView: View {
    let rx: [Double]
    let tx: [Double]
    var height: CGFloat = 44

    var body: some View {
        Canvas { context, size in
            let peak = max(rx.max() ?? 0, tx.max() ?? 0)
            // A floor keeps an idle link flat instead of amplifying noise.
            let scale = max(peak, 1_000_000)

            for series in [
                (values: tx, color: Theme.upload),
                (values: rx, color: Theme.download),
            ] {
                let line = Self.path(for: series.values, in: size, scale: scale, closed: false)
                let area = Self.path(for: series.values, in: size, scale: scale, closed: true)
                context.fill(area, with: .color(series.color.opacity(0.18)))
                context.stroke(line, with: .color(series.color), lineWidth: 1.5)
            }
        }
        .frame(height: height)
        .background(Theme.surfaceRaised.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private static func path(
        for values: [Double],
        in size: CGSize,
        scale: Double,
        closed: Bool
    ) -> Path {
        var path = Path()
        guard values.count > 1, size.width > 0, size.height > 0 else { return path }

        let stepX = size.width / CGFloat(values.count - 1)
        // Leave a pixel of headroom so a peak is not clipped by the frame.
        let usableHeight = size.height - 2

        for (index, value) in values.enumerated() {
            let normalized = min(max(value / scale, 0), 1)
            let point = CGPoint(
                x: CGFloat(index) * stepX,
                y: size.height - 1 - CGFloat(normalized) * usableHeight
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        if closed {
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
        return path
    }
}
