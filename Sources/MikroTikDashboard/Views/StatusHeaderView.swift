import SwiftUI
import MikroTikKit

/// Title bar: router identity, aggregate WAN throughput and connection state.
struct StatusHeaderView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MikroTik")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(model.config.host)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer(minLength: 8)

            AggregateTile(
                title: "WAN DOWN",
                value: Formatting.bitsPerSecond(totalRx),
                color: Theme.download
            )
            AggregateTile(
                title: "WAN UP",
                value: Formatting.bitsPerSecond(totalTx),
                color: Theme.upload
            )
            AggregateTile(
                title: "ACTIVE ROUTE",
                value: model.snapshot.activeRouteLabel,
                color: Theme.accent
            )

            connectionPill
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.surface.opacity(0.65))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private var totalRx: Double {
        model.snapshot.wanInterfaces.reduce(0) { $0 + $1.rxBitsPerSecond }
    }

    private var totalTx: Double {
        model.snapshot.wanInterfaces.reduce(0) { $0 + $1.txBitsPerSecond }
    }

    private var connectionPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isHealthy ? Theme.download : Theme.danger)
                .frame(width: 7, height: 7)
            Text(model.connectionSummary)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: 190, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surfaceRaised)
        .clipShape(Capsule())
        .help(model.connectionSummary)
    }
}

private struct AggregateTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(minWidth: 82, alignment: .trailing)
    }
}
