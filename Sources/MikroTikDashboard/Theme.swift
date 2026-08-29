import SwiftUI
import MikroTikKit

/// Dark palette shared by the window, the menu bar popover and the widget.
enum Theme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let surfaceRaised = Color(red: 0.15, green: 0.16, blue: 0.20)
    static let border = Color.white.opacity(0.08)
    static let borderActive = Color(red: 0.29, green: 0.62, blue: 1.0).opacity(0.55)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.35)

    static let accent = Color(red: 0.29, green: 0.62, blue: 1.0)
    static let download = Color(red: 0.30, green: 0.80, blue: 0.52)
    static let upload = Color(red: 0.98, green: 0.63, blue: 0.28)
    static let danger = Color(red: 0.95, green: 0.34, blue: 0.34)
    static let idle = Color.white.opacity(0.25)

    static func statusColor(for interface: InterfaceSnapshot) -> Color {
        guard !interface.isDisabled else { return idle }
        guard interface.isRunning else { return danger }
        if interface.role == .wan && interface.pingStatus == .down { return upload }
        return download
    }

    static func statusLabel(for interface: InterfaceSnapshot) -> String {
        if interface.isDisabled { return "disabled" }
        if !interface.isRunning { return "link down" }
        if interface.role == .wan {
            switch interface.pingStatus {
            case .up: return "online"
            case .down: return "no internet"
            case .unknown: return "running"
            }
        }
        return "running"
    }
}

extension View {
    /// Standard card chrome: rounded surface, hairline border, optional accent.
    func cardStyle(isHighlighted: Bool = false) -> some View {
        self
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? Theme.borderActive : Theme.border,
                        lineWidth: isHighlighted ? 1.5 : 1
                    )
            )
    }
}
