import AppKit
import SwiftUI
import MikroTikKit

enum DashboardWindow {
    static let id = "dashboard"
}

@main
struct MikroTikDashboardApp: App {
    @StateObject private var model = DashboardModel()

    var body: some Scene {
        Window("MikroTik Dashboard", id: DashboardWindow.id) {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 700, minHeight: 460)
        }
        .defaultSize(width: 860, height: 660)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Now") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Ping WAN Interfaces") {
                    model.pingNow()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            WindowModeCommands()
        }

        // Floating desktop card. Declared after the dashboard so the dashboard
        // stays the window opened at launch.
        Window("Desktop Widget", id: DesktopWidgetWindow.id) {
            DesktopWidgetView()
                .environmentObject(model)
        }
        .defaultSize(width: DesktopWidgetWindow.width, height: DesktopWidgetWindow.height)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            // Rendered as live text in the menu bar: "12.4M / 1.1M".
            Text(model.menuBarTitle)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

/// Window menu entries for moving between the two presentations.
private struct WindowModeCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Show Desktop Widget") {
                openWindow(id: DesktopWidgetWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("w", modifiers: [.command, .option])

            Button("Show Full Dashboard") {
                openWindow(id: DashboardWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("d", modifiers: [.command, .option])

            Button("Hide Desktop Widget") {
                dismissWindow(id: DesktopWidgetWindow.id)
            }

            Divider()
        }
    }
}
