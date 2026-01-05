import SwiftUI
import AppKit

struct HotKeySectionView: View {
    @Binding var configuration: HotkeyConfiguration
    @Binding var isSettingHotKey: Bool
    @Binding var currentModifiers: NSEvent.ModifierFlags
    @State private var keyMonitor: Any?
    
    var body: some View {
        Section("Global Shortcut") {
            VStack(spacing: 12) {
                // Hot key view (centered like in Hex)
                HStack {
                    Spacer()
                    HotKeyView(
                        configuration: isSettingHotKey ? 
                            HotkeyConfiguration(keyCode: 0, modifiers: currentModifiers) : 
                            configuration,
                        isActive: isSettingHotKey
                    )
                    .animation(.spring(), value: configuration.keyCode)
                    .animation(.spring(), value: currentModifiers)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    startSettingHotKey()
                }
                
                if !isSettingHotKey && configuration.keyCode == 0 && !configuration.modifiers.isEmpty {
                    Text("Modifier-only shortcut")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Click the area above then type the desired key combination")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func startSettingHotKey() {
        isSettingHotKey = true
        currentModifiers = []
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [self] event in
            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape
                    cancelSetting()
                    return nil
                }
                
                if !isModifierKey(event.keyCode) {
                    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                    
                    configuration = HotkeyConfiguration(
                        keyCode: event.keyCode,
                        modifiers: modifiers
                    )
                    
                    finishSetting()
                    return nil
                }
            } else if event.type == .flagsChanged {
                // Mettre à jour les modificateurs en temps réel
                currentModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            }
            
            return event
        }
    }
    
    private func cancelSetting() {
        isSettingHotKey = false
        currentModifiers = []
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func finishSetting() {
        isSettingHotKey = false
        currentModifiers = []
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        Settings.current.hotkey = configuration
        NotificationCenter.default.post(name: NSNotification.Name("HotkeyConfigurationChanged"), object: nil)
    }
    
    private func isModifierKey(_ keyCode: UInt16) -> Bool {
        let modifierKeyCodes: [UInt16] = [54, 55, 56, 60, 57, 58, 59, 62, 63]
        return modifierKeyCodes.contains(keyCode)
    }
}

// MARK: - Hot Key View
struct HotKeyView: View {
    var configuration: HotkeyConfiguration
    var isActive: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            // Afficher les modificateurs
            if configuration.modifiers.contains(.command) {
                KeyView(text: "⌘")
            }
            if configuration.modifiers.contains(.option) {
                KeyView(text: "⌥")
            }
            if configuration.modifiers.contains(.control) {
                KeyView(text: "⌃")
            }
            if configuration.modifiers.contains(.shift) {
                KeyView(text: "⇧")
            }
            
            // Afficher la touche principale
            if configuration.keyCode != 0 {
                let keyName = HotkeyConfiguration.displayName(for: configuration.keyCode)
                KeyView(text: keyName)
            }
            
            if configuration.modifiers.isEmpty && configuration.keyCode == 0 {
                Text("")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .frame(width: 48, height: 48)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background {
            if isActive && configuration.keyCode == 0 && configuration.modifiers.isEmpty {
                Text("Enter a key combination")
                    .foregroundColor(.secondary)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(isActive ? 0.2 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isActive ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                }
        }
        .shadow(color: isActive ? Color.accentColor.opacity(0.2) : .clear, radius: 8, x: 0, y: 4)
        .animation(.bouncy(duration: 0.3), value: configuration.keyCode)
        .animation(.bouncy(duration: 0.3), value: isActive)
    }
    
    private func keyCodeToCharacter(keyCode: UInt16) -> String {
        HotkeyConfiguration.displayName(for: keyCode)
    }
}

// MARK: - Key View
struct KeyView: View {
    var text: String
    
    var body: some View {
        Text(text)
            .font(.title.weight(.bold))
            .foregroundColor(.white)
            .frame(width: 48, height: 48)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 4)
    }
}

