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
    @State private var publicIPEchoURL = ""
    @State private var publicIPInterval = 300.0
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("Router") {
                TextField("Management address", text: $host, prompt: Text("192.168.88.1"))
                Toggle("Use HTTPS", isOn: $useTLS)
                TextField("Username", text: $username, prompt: Text("admin"))
                SecureField("Password", text: $password)

                Text("The password is stored in your login Keychain, never on disk "
                     + "in the clear. A read-only RouterOS user is enough unless you "
                     + "want the per-link power button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("Public address") {
                Picker("Show", selection: Binding(
                    get: { model.addressMode },
                    set: { model.addressMode = $0 }
                )) {
                    ForEach(AddressMode.allCases, id: \.self) { mode in
                        Text("\(mode.label) address").tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Echo service", text: $publicIPEchoURL,
                          prompt: Text("http://ifconfig.me/ip"))

                HStack {
                    Slider(value: $publicIPInterval, in: 60...3600, step: 60)
                    Text("\(Int(publicIPInterval / 60))m")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }

                Text("The router fetches this URL once per interval, once per uplink, "
                     + "to learn the address your ISP presents. It is the only request "
                     + "this app makes outside your network — leave it blank to switch "
                     + "the lookup off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .disabled(
                            host.trimmingCharacters(in: .whitespaces).isEmpty
                                || username.trimmingCharacters(in: .whitespaces).isEmpty
                                || password.isEmpty
                        )
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
        publicIPEchoURL = config.publicIPEchoURL
        publicIPInterval = config.publicIPInterval
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
        config.publicIPEchoURL = publicIPEchoURL.trimmingCharacters(in: .whitespaces)
        config.publicIPInterval = publicIPInterval

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
