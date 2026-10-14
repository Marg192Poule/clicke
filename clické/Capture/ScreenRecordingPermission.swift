import AppKit
import CoreGraphics

// MARK: - Screen Recording Permission

/// `screencapture` runs on Clické's behalf, so macOS requires the Screen Recording permission
/// for Clické. Nothing is polled: the permission is only checked when a capture fails.
enum ScreenRecordingPermission {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    private static var isPresentingAlert = false

    /// Whether Clické may capture the screen. Doesn't prompt.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Explains why the capture failed and offers to open System Settings.
    static func presentGuidance() {
        guard !isPresentingAlert else { return }
        isPresentingAlert = true
        defer { isPresentingAlert = false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Allow Clické to Record Your Screen")
        alert.informativeText = String(localized: "Clické needs the Screen Recording permission to capture your screen. Turn on Clické in System Settings > Privacy & Security > Screen & System Audio Recording, then try again.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Not Now"))

        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }

    /// Registers Clické in the Screen Recording list, then opens that pane of System Settings.
    static func openSystemSettings() {
        // Adds Clické to the list (and shows the system prompt if it was never asked before).
        _ = CGRequestScreenCaptureAccess()
        if let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
