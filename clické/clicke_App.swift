import AppKit

/// Entry point.
///
/// Clické uses the AppKit life cycle rather than a SwiftUI `App`: it's a menu bar app whose windows
/// are managed by controllers (`SettingsWindowController`, `ScreenshotEditorWindow`), and owning the
/// main menu means ⌘, opens the real Settings window (SwiftUI's `Settings` scene showed an empty one).
@main
enum ClickeApp {
    /// `NSApplication.delegate` is weak: this keeps the delegate alive for the app's lifetime.
    private static let appDelegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.run()
    }
}
