import SwiftUI
import AppKit

/// Section view for configuring the window capture hotkey.
/// Uses the shared HotKeyRecorderView component.
struct TabCaptureHotKeySectionView: View {
    @Binding var configuration: HotkeyConfiguration
    @Binding var isSettingHotKey: Bool
    @Binding var currentModifiers: NSEvent.ModifierFlags
    
    var body: some View {
        HotKeyRecorderView(
            sectionTitle: "Window Capture",
            description: "Configure the shortcut to capture the active window",
            configuration: $configuration,
            onConfigurationChanged: { newConfig in
                var settings = AppSettings.current
                settings.windowHotkey = newConfig
                AppSettings.current = settings
                NotificationCenter.default.post(name: NSNotification.Name("HotkeyConfigurationChanged"), object: nil)
            }
        )
    }
}
