import AppKit

// MARK: - App Delegate

/// App lifecycle: menus, global shortcuts, Dock icon visibility, files opened from Finder.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager { mode in
        CaptureController.shared.capture(mode)
    }

    // MARK: - Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Info.plist sets LSUIElement, so a hidden Dock icon never flashes at launch; show it now
        // if wanted. Set unconditionally: `activationPolicy()` isn't reliable before launch completes.
        NSApp.setActivationPolicy(Self.desiredActivationPolicy)
        NSApp.mainMenu = MenuController.shared.makeMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CaptureTemporaryStorage.removeAll()
        statusItem = MenuController.shared.makeStatusItem()
        hotkeyManager.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .settingsDidChange,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Dock

    /// Clicking the Dock icon with no window open shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // `flag` also counts floating panels (capture preview, toast): look for real windows.
        let hasDocumentWindow = sender.windows.contains { $0.isVisible && $0.canBecomeMain }
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

    @objc private func settingsDidChange() {
        applyActivationPolicy()
        MenuController.shared.refreshShortcuts()
    }

    private static var desiredActivationPolicy: NSApplication.ActivationPolicy {
        AppSettings.current.showDockIcon ? .regular : .accessory
    }

    /// Shows or hides the Dock icon (and the main menu bar) when `showDockIcon` changes.
    private func applyActivationPolicy() {
        let policy = Self.desiredActivationPolicy
        guard NSApp.activationPolicy() != policy else { return }

        let keyWindow = NSApp.keyWindow
        NSApp.setActivationPolicy(policy)

        // Changing the policy deactivates the app: keep the window in use (e.g. Settings) in front.
        if let keyWindow, keyWindow.isVisible {
            NSApp.activate()
            keyWindow.makeKeyAndOrderFront(nil)
        }
    }
}
