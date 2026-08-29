import SwiftUI
import MikroTikKit

/// One interface: identity, health, live rate, sparkline and lifetime totals.
struct InterfaceCardView: View {
    @EnvironmentObject private var model: DashboardModel

    let interface: InterfaceSnapshot
    let history: TrafficHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Group {
                rates
                SparklineView(rx: history.rx, tx: history.tx)
                totals
                if interface.role == .wan {
                    connectionTest
                }
            }
            // A disabled interface has no live data worth reading; grey out
            // everything but the header so the toggle stays legible.
            .opacity(interface.isDisabled ? 0.4 : 1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(isHighlighted: interface.isActiveGateway)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            identity
            if interface.role == .wan {
                powerButton
            }
        }
    }

    /// Kept separate from the power button so combining these labels for
    /// VoiceOver does not swallow the button.
    private var identity: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.statusColor(for: interface))
                .frame(width: 9, height: 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(interface.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if interface.isActiveGateway {
                        BadgeLabel(text: "ACTIVE", color: Theme.accent)
                    }

                    if interface.isDisabled {
                        BadgeLabel(text: "DISABLED", color: Theme.danger)
                    }
                }

                Text(interface.ipAddress ?? "no address")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Theme.statusLabel(for: interface).uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.statusColor(for: interface))

                if interface.role == .wan {
                    pingBadge
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(interface.name), \(Theme.statusLabel(for: interface))"
        )
    }

    // MARK: - Enable / disable

    private var isToggling: Bool {
        model.isTogglingInterface(interface.name)
    }

    private var powerButton: some View {
        Button {
            model.setInterfaceDisabled(!interface.isDisabled, forInterface: interface.name)
        } label: {
            Group {
                if isToggling {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(interface.isDisabled ? Theme.textTertiary : Theme.download)
                }
            }
            .frame(width: 24, height: 24)
            .background(Theme.surfaceRaised)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(
                    interface.isDisabled ? Theme.border : Theme.download.opacity(0.35),
                    lineWidth: 1
                )
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isToggling)
        .help(interface.isDisabled ? "Enable \(interface.name)" : "Disable \(interface.name)")
        .accessibilityLabel(
            interface.isDisabled
                ? "Enable \(interface.name)"
                : "Disable \(interface.name)"
        )
        .accessibilityHint(isToggling ? "Applying change" : "")
    }

    private var pingBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(pingColor)
                .frame(width: 6, height: 6)
            Text(pingText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var pingColor: Color {
        switch interface.pingStatus {
        case .up: return Theme.download
        case .down: return Theme.danger
        case .unknown: return Theme.idle
        }
    }

    private var pingText: String {
        switch interface.pingStatus {
        case .up: return Formatting.latency(interface.pingLatency)
        case .down: return "no reply"
        case .unknown: return "…"
        }
    }

    private var rates: some View {
        HStack(spacing: 10) {
            RateTile(
                symbol: "arrow.down",
                label: "Download",
                value: interface.rxBitsPerSecond,
                color: Theme.download
            )
            RateTile(
                symbol: "arrow.up",
                label: "Upload",
                value: interface.txBitsPerSecond,
                color: Theme.upload
            )
        }
    }

    private var totals: some View {
        HStack(spacing: 0) {
            TotalLabel(title: "RX total", value: Formatting.bytes(interface.rxBytes))
            Spacer(minLength: 8)
            TotalLabel(title: "TX total", value: Formatting.bytes(interface.txBytes), alignment: .center)
            Spacer(minLength: 8)
            TotalLabel(title: "Combined", value: Formatting.bytes(interface.totalBytes), alignment: .trailing)
        }
    }

    // MARK: - On-demand connection test

    private var testState: ConnectionTestState? {
        model.connectionTest(for: interface.name)
    }

    private var isTesting: Bool {
        testState == .running
    }

    private var connectionTest: some View {
        HStack(spacing: 8) {
            Button {
                model.testConnection(forInterface: interface.name)
            } label: {
                Label("Test Connection", systemImage: "wifi")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isTesting ? Theme.textTertiary : Theme.accent)
            .disabled(isTesting)

            testResult

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch testState {
        case .running?:
            HStack(spacing: 5) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("testing…")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
        case .finished(let outcome)?:
            HStack(spacing: 4) {
                Image(systemName: outcome.isReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 10))
                Text(outcome.isReachable ? Formatting.latency(outcome.averageLatency) : "no reply")
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(outcome.isReachable ? Theme.download : Theme.danger)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                outcome.isReachable
                    ? "Connection test succeeded, \(Formatting.latency(outcome.averageLatency))"
                    : "Connection test failed, no reply"
            )
        case nil:
            EmptyView()
        }
    }
}

private struct BadgeLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.22))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private struct RateTile: View {
    let symbol: String
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(color)

            Text(Formatting.bitsPerSecond(value))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(Formatting.bitsPerSecond(value))")
    }
}

private struct TotalLabel: View {
    let title: String
    let value: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
