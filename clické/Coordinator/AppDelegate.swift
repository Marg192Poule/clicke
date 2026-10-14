import AppKit

// MARK: - App Delegate

/// App lifecycle: menus, global shortcuts, Dock icon visibility, files opened from Finder,
/// first launch and quitting.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set after the first launch (the Screen Recording onboarding is shown only once).
    private static let hasLaunchedBeforeKey = "HasLaunchedBefore"

    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager { mode in
        CaptureController.shared.capture(mode)
    }

    // MARK: - Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Info.plist sets LSUIElement, so a hidden Dock icon never flashes at launch; show it now if wanted.
        ActivationPolicyManager.shared.applyLaunchPolicy()
        NSApp.mainMenu = MenuController.shared.makeMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Leftovers of a session that crashed, and the drag folder of earlier versions.
        CaptureTemporaryStorage.removeAll()
        statusItem = MenuController.shared.makeStatusItem()
        hotkeyManager.start()
        ActivationPolicyManager.shared.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .settingsDidChange,
            object: nil
        )

        showOnboardingIfNeeded()
    }

    /// The first time Clické runs without the Screen Recording permission, Settings opens on the
    /// Capture tab, which explains the permission and asks for it.
    private func showOnboardingIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.hasLaunchedBeforeKey) else { return }
        defaults.set(true, forKey: Self.hasLaunchedBeforeKey)

        if !ScreenRecordingPermission.isGranted {
            SettingsWindowController.shared.show(tab: .capture)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Quitting

    /// Edits that were never copied, saved or dragged out aren't lost silently: the editor asks first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let editor = ScreenshotEditorWindow.shared
        guard editor.isOpen, editor.hasUnexportedChanges else { return .terminateNow }

        editor.bringToFront()

        // The editor may answer right away (synchronously) or after a sheet: `reply(toApplicationShouldTerminate:)`
        // is only valid once `.terminateLater` has been returned.
        var immediateAnswer: Bool?
        var isWaitingForReply = false
        editor.confirmDiscardingChanges { canQuit in
            if isWaitingForReply {
                NSApp.reply(toApplicationShouldTerminate: canQuit)
            } else {
                immediateAnswer = canQuit
            }
        }
        if let immediateAnswer {
            return immediateAnswer ? .terminateNow : .terminateCancel
        }
        isWaitingForReply = true
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
        NotificationCenter.default.removeObserver(self)
        CaptureTemporaryStorage.removeAll()
    }

    // MARK: - Dock

    /// Clicking the Dock icon with no window open shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // `flag` also counts floating panels (capture preview, toast): look for real windows.
        let hasDocumentWindow = sender.windows.contains { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }
        guard !hasDocumentWindow else { return true }

        if let minimized = sender.windows.first(where: { $0.isMiniaturized }) {
            minimized.deminiaturize(nil)
        } else {
            SettingsWindowController.shared.show()
        }
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MenuController.shared.makeDockMenu()
    }

    // MARK: - Opening Files

    /// Images dropped on the app icon or opened with "Open With" go to the editor.
    func application(_ application: NSApplication, open urls: [URL]) {
        CaptureController.shared.openImages(at: urls)
    }

    // MARK: - Settings

    /// The Dock icon follows the settings through `ActivationPolicyManager`; menus show the new shortcuts.
    @objc private func settingsDidChange() {
        MenuController.shared.refreshShortcuts()
    }
}
