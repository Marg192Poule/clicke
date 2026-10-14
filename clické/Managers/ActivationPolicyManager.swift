import AppKit

// MARK: - Activation Policy Manager

/// Decides whether Clické appears in the Dock, the app switcher (⌘Tab) and the menu bar.
///
/// - "Show in Dock" on: always (`.regular`).
/// - "Show in Dock" off: a menu bar app (`.accessory`), except while one of its windows (editor,
///   Settings) is open or minimized. Otherwise a window buried under other apps couldn't be found
///   again: no Dock icon, no ⌘Tab, no Window menu. Panels (preview, toasts, alerts, Open/Save
///   panels) don't count.
///
/// Changing the policy can deactivate the app and send its windows behind other apps: the window
/// the user was working in is brought back to the front.
final class ActivationPolicyManager: NSObject {
    static let shared = ActivationPolicyManager()

    /// Delay before going back to `.accessory`, so closing a window and opening another one
    /// (e.g. "Choose Folder…" opening Settings) doesn't make the Dock icon flicker.
    private static let demotionDelay: Duration = .milliseconds(300)

    private var isStarted = false
    private var isUpdateScheduled = false
    private var demotionTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    /// The policy at launch, before any window exists (`activationPolicy()` isn't reliable before
    /// launch completes, so it's set unconditionally).
    func applyLaunchPolicy() {
        NSApp.setActivationPolicy(AppSettings.current.showDockIcon ? .regular : .accessory)
    }

    /// Starts following windows and settings.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        let center = NotificationCenter.default
        let windowNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]
        for name in windowNotifications {
            center.addObserver(self, selector: #selector(stateDidChange(_:)), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(stateDidChange(_:)), name: NSApplication.didUnhideNotification, object: nil)
        center.addObserver(self, selector: #selector(stateDidChange(_:)), name: .settingsDidChange, object: nil)

        update()
    }

    // MARK: Updating

    @objc private func stateDidChange(_ notification: Notification) {
        scheduleUpdate()
    }

    /// Coalesces bursts of notifications, and waits for the end of the current event: a window is
    /// still visible while `willClose` is posted.
    private func scheduleUpdate() {
        guard !isUpdateScheduled else { return }
        isUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isUpdateScheduled = false
            update()
        }
    }

    private func update() {
        // A hidden app (⌘H) has no visible window, yet must keep its Dock icon to be unhidden.
        guard !NSApp.isHidden else { return }

        if wantsRegularPolicy {
            demotionTask?.cancel()
            demotionTask = nil
            apply(.regular)
        } else if NSApp.activationPolicy() != .accessory, demotionTask == nil {
            demotionTask = Task { [weak self] in
                try? await Task.sleep(for: Self.demotionDelay)
                guard let self, !Task.isCancelled else { return }
                demotionTask = nil
                if !NSApp.isHidden, !wantsRegularPolicy {
                    apply(.accessory)
                }
            }
        }
    }

    private var wantsRegularPolicy: Bool {
        AppSettings.current.showDockIcon || hasOpenWindow
    }

    /// Whether a regular window of Clické (not a panel) is on screen or in the Dock.
    private var hasOpenWindow: Bool {
        NSApp.windows.contains { window in
            Self.isRegularWindow(window) && (window.isVisible || window.isMiniaturized)
        }
    }

    private static func isRegularWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.canBecomeMain
    }

    private func apply(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }

        // Promotion always follows a window being shown (and the app asked to activate), possibly
        // before the activation completed: keep that window in front even if the app isn't active yet.
        let frontWindow: NSWindow?
        if policy == .regular {
            frontWindow = NSApp.keyWindow ?? NSApp.mainWindow
                ?? NSApp.orderedWindows.first { Self.isRegularWindow($0) && $0.isVisible }
        } else {
            frontWindow = NSApp.isActive ? (NSApp.keyWindow ?? NSApp.mainWindow) : nil
        }
        NSApp.setActivationPolicy(policy)

        // Keep the window in use in front (switching policy may have deactivated the app).
        guard let frontWindow else { return }
        DispatchQueue.main.async {
            guard frontWindow.isVisible else { return }
            NSApp.activate()
            frontWindow.makeKeyAndOrderFront(nil)
        }
    }
}
