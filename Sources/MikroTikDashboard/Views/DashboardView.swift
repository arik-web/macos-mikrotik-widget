import SwiftUI
import MikroTikKit

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel

    private let columns = [GridItem(.adaptive(minimum: 330), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            StatusHeaderView()

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

            footer
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
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
