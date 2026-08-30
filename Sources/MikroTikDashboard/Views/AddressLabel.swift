import AppKit
import SwiftUI
import MikroTikKit

/// Which address an interface row shows. Public is the default: it is the one
/// worth reading at a glance and the one people paste elsewhere.
enum AddressMode: String, CaseIterable, Codable {
    case publicAddress
    case localAddress

    var toggled: AddressMode { self == .publicAddress ? .localAddress : .publicAddress }

    var label: String {
        switch self {
        case .publicAddress: return "Public"
        case .localAddress: return "Local"
        }
    }
}

/// The address on an interface row: click to copy, right-click to switch which
/// one is shown, with a brief "Copied" acknowledgement.
struct AddressLabel: View {
    @EnvironmentObject private var model: DashboardModel

    let interface: InterfaceSnapshot
    var fontSize: CGFloat = 9

    @State private var justCopied = false
    @State private var isHovering = false

    private var shown: String? {
        switch model.addressMode {
        case .publicAddress: return interface.publicIPAddress
        case .localAddress: return interface.ipAddress
        }
    }

    /// A WAN with no public address yet should still show something useful,
    /// so fall back to the local one rather than a dash.
    private var displayed: String {
        shown ?? interface.ipAddress ?? "—"
    }

    private var isFallback: Bool { shown == nil && interface.ipAddress != nil }

    var body: some View {
        Text(justCopied ? "Copied" : displayed)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(
                justCopied
                    ? Theme.download
                    : (isFallback ? Theme.textTertiary : Theme.textSecondary)
            )
            .lineLimit(1)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(isHovering && copyable != nil ? 0.10 : 0))
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture { copy() }
            .help(helpText)
            .contextMenu {
                ForEach(AddressMode.allCases, id: \.self) { mode in
                    Button {
                        model.addressMode = mode
                    } label: {
                        // A check mark reads better than a disabled row.
                        Text(mode == model.addressMode ? "✓ \(mode.label) address"
                                                       : "   \(mode.label) address")
                    }
                }
                Divider()
                Button("Copy \(model.addressMode.label.lowercased()) address") { copy() }
                    .disabled(copyable == nil)
                if let other = otherAddress {
                    Button("Copy \(model.addressMode.toggled.label.lowercased()) address") {
                        write(other)
                    }
                }
            }
            .accessibilityLabel("\(model.addressMode.label) address \(displayed)")
            .accessibilityHint("Activate to copy")
    }

    private var copyable: String? { shown ?? interface.ipAddress }

    private var otherAddress: String? {
        switch model.addressMode {
        case .publicAddress: return interface.ipAddress
        case .localAddress: return interface.publicIPAddress
        }
    }

    private var helpText: String {
        guard let copyable else {
            return "No public address yet for \(interface.name)"
        }
        let kind = isFallback ? "local" : model.addressMode.label.lowercased()
        return "Click to copy \(interface.name)'s \(kind) address, \(copyable)."
            + " Right-click to switch between public and local."
    }

    private func copy() {
        guard let copyable else { return }
        write(copyable)
    }

    private func write(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        justCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            justCopied = false
        }
    }
}
