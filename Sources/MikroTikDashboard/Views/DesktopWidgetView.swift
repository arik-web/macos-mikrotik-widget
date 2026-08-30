import AppKit
import SwiftUI
import MikroTikKit

/// Compact always-on-top card: router health, one block per WAN, last update.
/// Deliberately narrow — it is meant to sit on the desktop, not be read across
/// the room, so every row is a single line of information.
struct DesktopWidgetView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.border)
            interfaces
            Divider().overlay(Theme.border)
            footer
        }
        .frame(width: DesktopWidgetWindow.width, height: DesktopWidgetWindow.height)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesktopWidgetWindow.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesktopWidgetWindow.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .background(DesktopWidgetWindowConfigurator())
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
    }

    /// Translucent dark glass, with the drag surface behind the whole card.
    private var cardBackground: some View {
        ZStack {
            WindowDragArea()
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Theme.background.opacity(0.72))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isHealthy ? Theme.download : Theme.danger)
                .frame(width: 7, height: 7)

            Text(model.config.host)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 4)

            SettingsIconButton()

            IconButton(symbol: "macwindow", help: "Switch to the full dashboard") {
                openWindow(id: DashboardWindow.id)
                NSApp.activate(ignoringOtherApps: true)
                dismissWindow(id: DesktopWidgetWindow.id)
            }

            IconButton(symbol: "xmark", help: "Close the desktop widget") {
                dismissWindow(id: DesktopWidgetWindow.id)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 9)
    }

    // MARK: - Interfaces

    @ViewBuilder
    private var interfaces: some View {
        let wans = model.snapshot.wanInterfaces

        if wans.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: model.lastError == nil ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle")
                    .font(.system(size: 20))
                    .foregroundStyle(model.lastError == nil ? Theme.textTertiary : Theme.danger)
                Text(model.lastError ?? "Waiting for the first reading…")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                if model.needsCredentials {
                    SettingsLink {
                        Text("Open Settings")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(wans) { interface in
                        CompactInterfaceView(interface: interface)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if let error = model.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.danger)
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(1)
                    .help(error)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.textTertiary)
                Text(lastUpdatedLabel)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 4)

            IconButton(symbol: "arrow.clockwise", help: "Refresh now") {
                Task { await model.refresh() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var lastUpdatedLabel: String {
        guard let lastUpdate = model.lastUpdate else { return "connecting…" }
        return "\(Self.clock.string(from: lastUpdate)) · \(Formatting.age(of: lastUpdate))"
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

/// One WAN, condensed to four lines: identity, rates, totals, test.
private struct CompactInterfaceView: View {
    @EnvironmentObject private var model: DashboardModel

    let interface: InterfaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            identity
            Group {
                rates
                totals
                connectionTest
            }
            .opacity(interface.isDisabled ? 0.4 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    interface.isActiveGateway ? Theme.borderActive : Theme.border,
                    lineWidth: 1
                )
        )
    }

    private var identity: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.statusColor(for: interface))
                .frame(width: 7, height: 7)

            Text(interface.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if interface.isActiveGateway {
                Text("ACTIVE")
                    .font(.system(size: 7, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.accent.opacity(0.22))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }

            if interface.isDisabled {
                Text("OFF")
                    .font(.system(size: 7, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.danger.opacity(0.22))
                    .foregroundStyle(Theme.danger)
                    .clipShape(Capsule())
            }

            Spacer(minLength: 4)

            Text(interface.ipAddress ?? "—")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(interface.name), \(Theme.statusLabel(for: interface))")

            powerButton
        }
    }

    // MARK: - Enable / disable

    private var isToggling: Bool {
        model.isTogglingInterface(interface.name)
    }

    /// Same control as the dashboard card, sized for the widget's rows.
    private var powerButton: some View {
        Button {
            model.setInterfaceDisabled(!interface.isDisabled, forInterface: interface.name)
        } label: {
            Group {
                if isToggling {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(interface.isDisabled ? Theme.textTertiary : Theme.download)
                }
            }
            .frame(width: 20, height: 20)
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

    private var rates: some View {
        HStack(spacing: 8) {
            CompactRate(
                symbol: "arrow.down",
                value: interface.rxBitsPerSecond,
                color: Theme.download
            )
            CompactRate(
                symbol: "arrow.up",
                value: interface.txBitsPerSecond,
                color: Theme.upload
            )
        }
    }

    private var totals: some View {
        HStack(spacing: 4) {
            Text("RX \(Formatting.bytes(interface.rxBytes))")
            Text("·")
            Text("TX \(Formatting.bytes(interface.txBytes))")
            Spacer(minLength: 0)
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(1)
    }

    // MARK: - On-demand connection test

    private var testState: ConnectionTestState? {
        model.connectionTest(for: interface.name)
    }

    private var connectionTest: some View {
        HStack(spacing: 6) {
            Button {
                model.testConnection(forInterface: interface.name)
            } label: {
                Label("Test", systemImage: "wifi")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(testState == .running ? Theme.textTertiary : Theme.accent)
            .disabled(testState == .running)

            testResult

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch testState {
        case .running?:
            HStack(spacing: 4) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                Text("testing…")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textSecondary)
            }
        case .finished(let outcome)?:
            HStack(spacing: 3) {
                Image(systemName: outcome.isReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 9))
                Text(outcome.isReachable ? Formatting.latency(outcome.averageLatency) : "no reply")
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundStyle(outcome.isReachable ? Theme.download : Theme.danger)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                outcome.isReachable
                    ? "Connection test succeeded, \(Formatting.latency(outcome.averageLatency))"
                    : "Connection test failed, no reply"
            )
        case nil:
            // Falls back to the background ping so the row is never blank.
            Text(Theme.statusLabel(for: interface))
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct CompactRate: View {
    let symbol: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
            Text(Formatting.bitsPerSecond(value))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(symbol == "arrow.down" ? "Download" : "Upload") \(Formatting.bitsPerSecond(value))"
        )
    }
}

/// Opens the Settings scene, styled to match `IconButton`.
///
/// `SettingsLink` is the supported way to reach Settings from a window that is
/// not the main one; calling the private `showSettingsWindow:` selector breaks
/// across macOS releases.
private struct SettingsIconButton: View {
    @State private var isHovering = false

    var body: some View {
        SettingsLink {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(isHovering ? 0.12 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Router settings: address, username and password")
        .accessibilityLabel("Router settings")
    }
}

/// Borderless glyph button sized for the widget's title row.
private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(isHovering ? 0.12 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
