import SwiftUI
import AppKit

// MARK: - Generic HotKey Recorder Component

/// A reusable component for recording keyboard shortcuts.
/// Used by both screenshot and window capture hotkey sections.
struct HotKeyRecorderView: View {
    let sectionTitle: String
    let description: String
    @Binding var configuration: HotkeyConfiguration
    let onConfigurationChanged: (HotkeyConfiguration) -> Void
    
    @State private var isRecording = false
    @State private var currentModifiers: NSEvent.ModifierFlags = []
    @State private var keyMonitor: Any?
    
    var body: some View {
        Section(sectionTitle) {
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    HotKeyView(
                        configuration: isRecording ?
                            HotkeyConfiguration(keyCode: 0, modifiers: currentModifiers) :
                            configuration,
                        isActive: isRecording
                    )
                    .animation(.spring(), value: configuration.keyCode)
                    .animation(.spring(), value: currentModifiers)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    startRecording()
                }
                
                if !isRecording && configuration.keyCode == 0 && !configuration.modifiers.isEmpty {
                    Text("Modifier-only shortcut")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func startRecording() {
        isRecording = true
        currentModifiers = []
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [self] event in
            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape
                    cancelRecording()
                    return nil
                }
                
                if !isModifierKey(event.keyCode) {
                    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                    
                    let newConfig = HotkeyConfiguration(
                        keyCode: event.keyCode,
                        modifiers: modifiers
                    )
                    configuration = newConfig
                    
                    finishRecording()
                    return nil
                }
            } else if event.type == .flagsChanged {
                currentModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            }
            
            return event
        }
    }
    
    private func cancelRecording() {
        isRecording = false
        currentModifiers = []
        removeMonitor()
    }
    
    private func finishRecording() {
        isRecording = false
        currentModifiers = []
        removeMonitor()
        onConfigurationChanged(configuration)
    }
    
    private func removeMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func isModifierKey(_ keyCode: UInt16) -> Bool {
        let modifierKeyCodes: [UInt16] = [54, 55, 56, 60, 57, 58, 59, 62, 63]
        return modifierKeyCodes.contains(keyCode)
    }
}

// MARK: - Screenshot HotKey Section

/// Section view for configuring the screenshot capture hotkey.
struct HotKeySectionView: View {
    @Binding var configuration: HotkeyConfiguration
    @Binding var isSettingHotKey: Bool
    @Binding var currentModifiers: NSEvent.ModifierFlags
    
    var body: some View {
        HotKeyRecorderView(
            sectionTitle: "Global Shortcut",
            description: "Click the area above then type the desired key combination",
            configuration: $configuration,
            onConfigurationChanged: { newConfig in
                AppSettings.current.areaHotkey = newConfig
                NotificationCenter.default.post(name: NSNotification.Name("HotkeyConfigurationChanged"), object: nil)
            }
        )
    }
}

// MARK: - HotKey Display View

/// Visual representation of a keyboard shortcut with modifier keys.
struct HotKeyView: View {
    var configuration: HotkeyConfiguration
    var isActive: Bool
    
    var body: some View {
        HStack(spacing: 6) {
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
}

// MARK: - Single Key View

/// Visual representation of a single keyboard key.
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
