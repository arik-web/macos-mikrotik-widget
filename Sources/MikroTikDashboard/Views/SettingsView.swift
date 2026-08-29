import SwiftUI
import MikroTikKit

/// Editable copy of the router connection settings. Nothing is applied until
/// Save, so a half-typed host never breaks the poll loop.
struct SettingsView: View {
    @EnvironmentObject private var model: DashboardModel

    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var pollInterval = 2.0
    @State private var pingTarget = ""
    @State private var wanNames = ""
    @State private var lanNames = ""
    @State private var useTLS = false
    @State private var showAllInterfaces = false
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("Router") {
                TextField("Host", text: $host)
                Toggle("Use HTTPS", isOn: $useTLS)
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
            }

            Section("Polling") {
                HStack {
                    Slider(value: $pollInterval, in: 1...10, step: 1)
                    Text("\(Int(pollInterval))s")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                TextField("Ping target", text: $pingTarget)
            }

            Section("Interfaces") {
                TextField("WAN names (comma separated)", text: $wanNames)
                TextField("LAN names (comma separated)", text: $lanNames)
                Toggle("Show interfaces without an IP address", isOn: $showAllInterfaces)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Revert") { load() }
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { if !didLoad { load(); didLoad = true } }
    }

    private func load() {
        let config = model.config
        host = config.host
        useTLS = config.useTLS
        username = model.credentials.username
        password = model.credentials.password
        pollInterval = config.pollInterval
        pingTarget = config.pingTarget
        wanNames = config.wanInterfaceNames.joined(separator: ", ")
        lanNames = config.lanInterfaceNames.joined(separator: ", ")
        showAllInterfaces = config.showAllInterfaces
    }

    private func save() {
        var config = model.config
        config.host = host.trimmingCharacters(in: .whitespaces)
        config.useTLS = useTLS
        config.username = username
        config.pollInterval = pollInterval
        config.pingTarget = pingTarget.trimmingCharacters(in: .whitespaces)
        config.wanInterfaceNames = Self.split(wanNames)
        config.lanInterfaceNames = Self.split(lanNames)
        config.showAllInterfaces = showAllInterfaces

        model.applySettings(
            config: config,
            credentials: RouterCredentials(username: username, password: password)
        )
    }

    private static func split(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
