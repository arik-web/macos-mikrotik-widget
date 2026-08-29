import AppKit
import SwiftUI
import MikroTikKit

/// The popover behind the menu bar item: one compact row per interface.
struct MenuBarContentView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.config.host)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Circle()
                    .fill(model.isHealthy ? Theme.download : Theme.danger)
                    .frame(width: 7, height: 7)
                Text(model.connectionSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Divider().overlay(Theme.border)

            if model.snapshot.interfaces.isEmpty {
                Text("No data yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(model.snapshot.interfaces) { interface in
                    MenuBarRow(interface: interface)
                }
            }

            Divider().overlay(Theme.border)

            HStack {
                Button("Show Full Dashboard") {
                    openWindow(id: DashboardWindow.id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)

                Button("Show Desktop Widget") {
                    openWindow(id: DesktopWidgetWindow.id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)

                Spacer()

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 11))
        }
        .padding(12)
        .frame(width: 300)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

private struct MenuBarRow: View {
    let interface: InterfaceSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.statusColor(for: interface))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(interface.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(interface.ipAddress ?? "—")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text("↓ \(Formatting.bitsPerSecond(interface.rxBitsPerSecond))")
                    .foregroundStyle(Theme.download)
                Text("↑ \(Formatting.bitsPerSecond(interface.txBitsPerSecond))")
                    .foregroundStyle(Theme.upload)
            }
            .font(.system(size: 10, design: .monospaced))
            .monospacedDigit()
        }
    }
}
