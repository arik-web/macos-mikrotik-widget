import SwiftUI
import MikroTikKit

/// Loud, unmissable notice that the router has stopped answering.
///
/// The old treatment was a 7-point dot turning red while every number on the
/// card kept its last value — which reads as a healthy router on a quiet
/// network. During a freeze that is exactly the wrong impression, so this
/// states the condition in words and says how long it has been true.
struct UnreachableBanner: View {
    @EnvironmentObject private var model: DashboardModel

    /// Drives the pulse. A static red bar is easy to stop noticing.
    @State private var pulse = false

    var compact: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: compact ? 10 : 12, weight: .bold))

            VStack(alignment: .leading, spacing: 1) {
                Text("ROUTER NOT RESPONDING")
                    .font(.system(size: compact ? 10 : 12, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(detail)
                    .font(.system(size: compact ? 9 : 10, design: .monospaced))
                    .opacity(0.9)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                Task { await model.refresh() }
            } label: {
                Text("Retry")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger.opacity(pulse ? 0.95 : 0.70))
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Router not responding. \(detail)")
    }

    private var detail: String {
        var parts: [String] = []
        if let silent = model.silentFor {
            parts.append("silent \(Formatting.age(of: Date().addingTimeInterval(-silent)))")
        }
        parts.append("\(model.consecutiveFailures) failed polls")
        if let error = model.lastError { parts.append(error) }
        return parts.joined(separator: " · ")
    }
}
