import SwiftUI
import AppKit

struct TabCaptureHotKeySectionView: View {
    @Binding var configuration: HotkeyConfiguration
    @Binding var isSettingHotKey: Bool
    @Binding var currentModifiers: NSEvent.ModifierFlags
    @State private var keyMonitor: Any?
    @State private var isSettingTabHotKey = false
    @State private var tabCurrentModifiers: NSEvent.ModifierFlags = []
    
    var body: some View {
        Section("Window Capture") {
            VStack(spacing: 12) {
                // Hot key view
                HStack {
                    Spacer()
                    HotKeyView(
                        configuration: isSettingTabHotKey ? 
                            HotkeyConfiguration(keyCode: 0, modifiers: tabCurrentModifiers) : 
                            configuration,
                        isActive: isSettingTabHotKey
                    )
                    .animation(.spring(), value: configuration.keyCode)
                    .animation(.spring(), value: tabCurrentModifiers)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    startSettingTabHotKey()
                }
                
                if !isSettingTabHotKey && configuration.keyCode == 0 && !configuration.modifiers.isEmpty {
                    Text("Modifier-only shortcut")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Configure the shortcut to capture the active window")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func startSettingTabHotKey() {
        isSettingTabHotKey = true
        tabCurrentModifiers = []
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [self] event in
            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape
                    cancelSettingTabHotKey()
                    return nil
                }
                
                if !isModifierKey(event.keyCode) {
                    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                    
                    configuration = HotkeyConfiguration(
                        keyCode: event.keyCode,
                        modifiers: modifiers
                    )
                    
                    finishSettingTabHotKey()
                    return nil
                }
            } else if event.type == .flagsChanged {
                // Update modifiers in real-time
                tabCurrentModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            }
            
            return event
        }
    }
    
    private func cancelSettingTabHotKey() {
        isSettingTabHotKey = false
        tabCurrentModifiers = []
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func finishSettingTabHotKey() {
        isSettingTabHotKey = false
        tabCurrentModifiers = []
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        var settings = Settings.current
        settings.tabCaptureHotkey = configuration
        Settings.current = settings
        NotificationCenter.default.post(name: NSNotification.Name("HotkeyConfigurationChanged"), object: nil)
    }
    
    private func isModifierKey(_ keyCode: UInt16) -> Bool {
        let modifierKeyCodes: [UInt16] = [54, 55, 56, 60, 57, 58, 59, 62, 63]
        return modifierKeyCodes.contains(keyCode)
    }
}

