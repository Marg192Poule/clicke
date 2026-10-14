import AppKit
import CoreGraphics

// MARK: - Screen Recording Permission

/// `screencapture` runs on Clické's behalf, so macOS requires the Screen Recording permission
/// for Clické. Without it, captures only contain the wallpaper and the menu bar, so the permission
/// is checked before each capture. Nothing is polled.
enum ScreenRecordingPermission {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    private static let askedKey = "ScreenRecordingAccessRequested"

    private static var isPresentingGuidance = false

    /// Whether Clické may capture the screen. Doesn't prompt.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Whether `requestAccess()` was already called (macOS shows its prompt only once).
    static var hasRequestedAccess: Bool {
        UserDefaults.standard.bool(forKey: askedKey)
    }

    /// Called instead of capturing when the permission is missing. The first time, macOS's own
    /// prompt is enough (it offers to open System Settings); afterwards macOS stays silent, so
    /// Clické explains what to do.
    static func handleMissingAccess() {
        if hasRequestedAccess {
            presentGuidance()
        } else {
            requestAccess()
        }
    }

    /// Explains why Clické can't capture and offers to open System Settings.
    ///
    /// The alert never runs inside a `Task` (see `ModalAlert`), so it's safe to call from async code.
    static func presentGuidance() {
        guard !isPresentingGuidance else { return }
        isPresentingGuidance = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Allow Clické to Record Your Screen")
        alert.informativeText = String(localized: "Clické needs Screen Recording permission to take screenshots. Turn on Clické in System Settings > Privacy & Security > Screen & System Audio Recording. macOS may ask you to quit and reopen Clické.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Not Now"))

        ModalAlert.present(alert) { response in
            isPresentingGuidance = false
            if response == .alertFirstButtonReturn {
                requestAccess()
            }
        }
    }

    /// The single entry point for asking for Screen Recording access (used by captures and Settings).
    /// The first time, only the system prompt appears; afterwards (macOS never re-prompts), it opens
    /// the Screen & System Audio Recording pane of System Settings.
    static func requestAccess() {
        let alreadyAsked = hasRequestedAccess
        UserDefaults.standard.set(true, forKey: askedKey)
        // Also adds Clické to the Screen Recording list in System Settings.
        let granted = CGRequestScreenCaptureAccess()
        if !granted, alreadyAsked, let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
