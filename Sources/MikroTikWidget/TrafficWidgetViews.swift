import SwiftUI
import WidgetKit
import MikroTikKit

/// Palette kept in step with the app's `Theme`; the widget target does not
/// link the app, so the few colours it needs are declared here.
enum WidgetTheme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let surface = Color.white.opacity(0.07)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.35)
    static let accent = Color(red: 0.29, green: 0.62, blue: 1.0)
    static let download = Color(red: 0.30, green: 0.80, blue: 0.52)
    static let upload = Color(red: 0.98, green: 0.63, blue: 0.28)
    static let danger = Color(red: 0.95, green: 0.34, blue: 0.34)
    static let idle = Color.white.opacity(0.25)

    static func statusColor(for interface: InterfaceSnapshot) -> Color {
        if interface.isDisabled { return idle }
        if !interface.isRunning { return danger }
        if interface.role == .wan && interface.pingStatus == .down { return upload }
        return download
    }
}

struct TrafficWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrafficEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(snapshot: entry.snapshot)
            case .systemLarge:
                LargeWidgetView(snapshot: entry.snapshot)
            default:
                MediumWidgetView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(WidgetTheme.background, for: .widget)
    }
}

// MARK: - Small

private struct SmallWidgetView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeaderLine(snapshot: snapshot)

            Spacer(minLength: 0)

            if let wan = snapshot.primaryWAN {
                Text(wan.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetTheme.accent)
                    .lineLimit(1)

                SpeedLine(symbol: "arrow.down", value: wan.rxBitsPerSecond, color: WidgetTheme.download)
                SpeedLine(symbol: "arrow.up", value: wan.txBitsPerSecond, color: WidgetTheme.upload)
            } else {
                Text("No active WAN")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetTheme.textSecondary)
            }

            Spacer(minLength: 0)

            StatusDots(interfaces: snapshot.wanInterfaces)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium

private struct MediumWidgetView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderLine(snapshot: snapshot)

            HStack(alignment: .top, spacing: 10) {
                ForEach(displayed) { interface in
                    WANTile(interface: interface)
                }
            }

            Spacer(minLength: 0)

            FooterLine(snapshot: snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Falls back to whatever interfaces exist when none are tagged as WAN.
    private var displayed: [InterfaceSnapshot] {
        let wans = snapshot.wanInterfaces
        return Array((wans.isEmpty ? snapshot.interfaces : wans).prefix(2))
    }
}

// MARK: - Large

private struct LargeWidgetView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderLine(snapshot: snapshot)

            ForEach(snapshot.interfaces.prefix(4)) { interface in
                HStack(spacing: 8) {
                    Circle()
                        .fill(WidgetTheme.statusColor(for: interface))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(interface.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WidgetTheme.textPrimary)
                            if interface.isActiveGateway {
                                Text("ACTIVE")
                                    .font(.system(size: 7, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(WidgetTheme.accent.opacity(0.22))
                                    .foregroundStyle(WidgetTheme.accent)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(interface.ipAddress ?? "—")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(WidgetTheme.textTertiary)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("↓ \(Formatting.bitsPerSecond(interface.rxBitsPerSecond))")
                            .foregroundStyle(WidgetTheme.download)
                        Text("↑ \(Formatting.bitsPerSecond(interface.txBitsPerSecond))")
                            .foregroundStyle(WidgetTheme.upload)
                    }
                    .font(.system(size: 10, design: .monospaced))
                }
                .padding(8)
                .background(WidgetTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Spacer(minLength: 0)

            FooterLine(snapshot: snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Shared pieces

private struct HeaderLine: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "network")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WidgetTheme.accent)
            Text(snapshot.routerHost)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetTheme.textSecondary)
            Spacer(minLength: 0)
            if !snapshot.isReachable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.danger)
            }
        }
    }
}

private struct FooterLine: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Text("↓ \(Formatting.bytes(snapshot.totalRxBytes))")
            Text("↑ \(Formatting.bytes(snapshot.totalTxBytes))")
            Spacer(minLength: 0)
            Text(Formatting.age(of: snapshot.capturedAt))
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(WidgetTheme.textTertiary)
    }
}

private struct SpeedLine: View {
    let symbol: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
            Text(Formatting.bitsPerSecond(value))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct StatusDots: View {
    let interfaces: [InterfaceSnapshot]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(interfaces.prefix(3)) { interface in
                HStack(spacing: 3) {
                    Circle()
                        .fill(WidgetTheme.statusColor(for: interface))
                        .frame(width: 6, height: 6)
                    Text(interface.name)
                        .font(.system(size: 9))
                        .foregroundStyle(WidgetTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct WANTile: View {
    let interface: InterfaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(WidgetTheme.statusColor(for: interface))
                    .frame(width: 7, height: 7)
                Text(interface.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .lineLimit(1)
            }

            SpeedLine(symbol: "arrow.down", value: interface.rxBitsPerSecond, color: WidgetTheme.download)
            SpeedLine(symbol: "arrow.up", value: interface.txBitsPerSecond, color: WidgetTheme.upload)

            Text(interface.ipAddress ?? "—")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(WidgetTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WidgetTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
