import AppKit
import SwiftUI
import MikroTikKit

/// DHCP leases: what the router has handed out, and which of those are
/// reservations rather than whatever the pool happened to give.
struct LeasesView: View {
    @EnvironmentObject private var model: DashboardModel

    enum Filter: String, CaseIterable {
        case all = "All"
        case reserved = "Reserved"
        case dynamic = "Dynamic"
    }

    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var pendingRelease: DHCPLease?

    private var visible: [DHCPLease] {
        let byKind = model.leases.filter { lease in
            switch filter {
            case .all: return true
            case .reserved: return !lease.isDynamic
            case .dynamic: return lease.isDynamic
            }
        }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return byKind }
        return byKind.filter {
            $0.displayName.lowercased().contains(query)
                || $0.address.contains(query)
                || $0.macAddress.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider().overlay(Theme.border)

            if let error = model.leasesError, model.leases.isEmpty {
                message(error, isError: true)
            } else if model.leases.isEmpty {
                message(model.isLoadingLeases ? "Loading leases…" : "No leases yet", isError: false)
            } else {
                table
            }
        }
        .onAppear { if model.leases.isEmpty { model.loadLeases() } }
        .confirmationDialog(
            "Release this reservation?",
            isPresented: Binding(
                get: { pendingRelease != nil },
                set: { if !$0 { pendingRelease = nil } }
            ),
            presenting: pendingRelease
        ) { lease in
            Button("Release \(lease.address)", role: .destructive) {
                model.setLeaseReserved(false, lease: lease)
                pendingRelease = nil
            }
            Button("Cancel", role: .cancel) { pendingRelease = nil }
        } message: { lease in
            // Worth spelling out: RouterOS has no "make dynamic", so releasing
            // deletes the row and the device may come back on a different IP.
            Text("\(lease.displayName) keeps \(lease.address) only until its lease expires. "
                 + "The reservation is deleted, so the router may hand it a different "
                 + "address next time.")
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)

            TextField("Search name, IP or MAC", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Spacer()

            Text(countLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)

            Button {
                model.loadLeases()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.textSecondary)
            .disabled(model.isLoadingLeases)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// The denominator matters: "12 shown" alone hides how much was filtered.
    private var countLabel: String {
        let reserved = model.leases.filter { !$0.isDynamic }.count
        let shown = visible.count
        return "\(shown) of \(model.leases.count) · \(reserved) reserved"
    }

    private func message(_ text: String, isError: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle" : "list.bullet.rectangle")
                .font(.system(size: 26))
                .foregroundStyle(isError ? Theme.danger : Theme.textTertiary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(isError ? Theme.danger : Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Table

    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                ForEach(visible) { lease in
                    LeaseRow(lease: lease) { reserved in
                        if reserved {
                            model.setLeaseReserved(true, lease: lease)
                        } else {
                            pendingRelease = lease
                        }
                    }
                    Divider().overlay(Theme.border.opacity(0.5))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Device").frame(width: 190, alignment: .leading)
            Text("Address").frame(width: 110, alignment: .leading)
            Text("MAC").frame(width: 140, alignment: .leading)
            Text("State").frame(width: 70, alignment: .leading)
            Spacer(minLength: 0)
            Text("Reserved").frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .textCase(.uppercase)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.surface.opacity(0.4))
    }
}

/// One lease. The toggle is the whole point of the tab, so it stays legible
/// even while a write is in flight.
private struct LeaseRow: View {
    @EnvironmentObject private var model: DashboardModel

    let lease: DHCPLease
    let setReserved: (Bool) -> Void

    @State private var isHovering = false
    @State private var justCopied = false

    private var isWriting: Bool { model.isWritingLease(lease.id) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(lease.displayName)
                    .font(.system(size: 12, weight: lease.isDynamic ? .regular : .medium))
                    .foregroundStyle(lease.hasName ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                if let server = lease.server, !server.isEmpty {
                    Text(server)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 190, alignment: .leading)

            Text(justCopied ? "Copied" : lease.address)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(justCopied ? Theme.download : Theme.textSecondary)
                .frame(width: 110, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { copy(lease.address) }
                .help("Click to copy \(lease.address)")

            Text(lease.macAddress)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 140, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { copy(lease.macAddress) }
                .help("Click to copy \(lease.macAddress)")

            HStack(spacing: 4) {
                Circle()
                    .fill(lease.isBound ? Theme.download : Theme.idle)
                    .frame(width: 6, height: 6)
                Text(lease.status ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 70, alignment: .leading)

            Spacer(minLength: 0)

            Group {
                if isWriting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Toggle("", isOn: Binding(
                        get: { !lease.isDynamic },
                        set: { setReserved($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
            .frame(width: 80, alignment: .trailing)
            .help(lease.isDynamic
                  ? "Reserve \(lease.address) for this device"
                  : "Release this reservation back to the pool")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(isHovering ? Color.white.opacity(0.04) : .clear)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(lease.displayName), \(lease.address), \(lease.kindLabel), \(lease.status ?? "unknown")"
        )
    }

    private func copy(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        justCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            justCopied = false
        }
    }
}
