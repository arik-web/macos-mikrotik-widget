import SwiftUI
import MikroTikKit

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel

    private let columns = [GridItem(.adaptive(minimum: 330), spacing: 14)]

    enum Tab: String, CaseIterable {
        case interfaces = "Interfaces"
        case leases = "DHCP"
    }

    @State private var tab: Tab = .interfaces

    var body: some View {
        VStack(spacing: 0) {
            StatusHeaderView()

            tabBar

            switch tab {
            case .interfaces:
                if model.snapshot.interfaces.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(model.snapshot.interfaces) { interface in
                                InterfaceCardView(
                                    interface: interface,
                                    history: model.history(for: interface.name)
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            case .leases:
                LeasesView()
            }

            footer
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { candidate in
                Button {
                    tab = candidate
                } label: {
                    Text(candidate.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tab == candidate ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            // Underline the active tab rather than filling it:
                            // the cards below already carry a lot of colour.
                            Rectangle()
                                .fill(tab == candidate ? Theme.accent : .clear)
                                .frame(height: 2),
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == candidate ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .background(Theme.surface.opacity(0.35))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: model.lastError == nil ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(model.lastError == nil ? Theme.textTertiary : Theme.danger)
            Text(model.lastError ?? "Waiting for the first reading from \(model.config.host)…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Retry now") {
                Task { await model.refresh() }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(
                "polling every \(String(format: "%.0f", model.config.pollInterval))s",
                systemImage: "timer"
            )
            .font(.system(size: 10))
            .foregroundStyle(Theme.textTertiary)

            Spacer()

            Button {
                model.pingNow()
            } label: {
                Label("Ping WANs", systemImage: "wave.3.right")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.textSecondary)

            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.5))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}
