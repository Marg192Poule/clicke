import AppKit
import SwiftUI

/// Shows short HUD messages ("Copied", "Saved", errors…) at the top of the screen under the pointer.
///
/// There's a single shared HUD: a new message replaces the current one instead of stacking.
/// The HUD never takes focus nor intercepts clicks.
final class ToastManager {

    // MARK: - Singleton

    static let shared = ToastManager()

    private init() {}

    // MARK: - Properties

    private static let displayDuration: Duration = .seconds(1.6)
    private static let topMargin: CGFloat = 12

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ToastView>?
    private var dismissTask: Task<Void, Never>?
    /// Incremented for each message, so a fade-out that finishes late doesn't hide a newer one.
    private var generation = 0

    // MARK: - Show Toast

    /// Shows a toast notification.
    /// - Parameters:
    ///   - message: The message to display (already localized).
    ///   - icon: The SF Symbol name for the icon.
    ///   - success: Whether this is a success or error toast.
    func show(message: String, icon: String, success: Bool) {
        generation += 1
        let toast = ToastView(message: message, icon: icon, success: success)

        let panel = panel ?? makePanel()
        let hostingView: NSHostingView<ToastView>
        if let existing = self.hostingView {
            existing.rootView = toast
            hostingView = existing
        } else {
            hostingView = NSHostingView(rootView: toast)
            panel.contentView = hostingView
            self.hostingView = hostingView
        }

        let size = hostingView.fittingSize
        if let screen = ScreenLocator.screenUnderPointer() {
            let visibleFrame = screen.visibleFrame
            panel.setFrame(
                NSRect(
                    x: (visibleFrame.midX - size.width / 2).rounded(),
                    y: visibleFrame.maxY - size.height - Self.topMargin,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )

        let token = generation
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled else { return }
            self?.fadeOut(token: token)
        }
    }

    // MARK: - Private

    private func fadeOut(token: Int) {
        guard let panel, token == generation else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // A newer toast may have appeared during the fade: keep it on screen.
            guard let self, token == generation else { return }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none
        self.panel = panel
        return panel
    }
}
