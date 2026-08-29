import AppKit
import SwiftUI

/// Identity and geometry of the floating desktop widget window.
///
/// WidgetKit refuses to list an ad-hoc signed extension in the widget gallery,
/// so the same information is served by a small always-on-top window instead.
enum DesktopWidgetWindow {
    static let id = "desktop-widget"
    static let width: CGFloat = 280
    static let height: CGFloat = 320
    static let cornerRadius: CGFloat = 16
}

/// Applies the chrome a SwiftUI `Window` scene cannot express: floating level,
/// a transparent frame so the rounded content shows through, no traffic lights
/// and presence on every Space.
///
/// Attached as a zero-size background view because reaching the `NSWindow`
/// requires being inside its view hierarchy.
struct DesktopWidgetWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguringView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // SwiftUI finishes installing its own chrome after this callback,
            // so the styling is re-applied once the run loop drains.
            configure()
            DispatchQueue.main.async { [weak self] in self?.configure() }
        }

        private func configure() {
            guard let window else { return }

            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            // A clear frame lets the SwiftUI content draw its own rounded,
            // translucent card; the shadow is recomputed from that alpha.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.invalidateShadow()

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.animationBehavior = .utilityWindow

            // The card draws its own close and mode buttons.
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
        }
    }
}

/// Transparent drag surface. Mouse-downs that SwiftUI does not claim land here
/// and move the window, so the widget can be dragged by its background.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
