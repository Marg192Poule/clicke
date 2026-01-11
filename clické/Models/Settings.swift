import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Capture Sound

/// Available system sounds for capture feedback.
enum CaptureSound: String, Codable, CaseIterable, Identifiable {
    case hero = "Hero"
    case submarine = "Submarine"
    case blow = "Blow"
    case frog = "Frog"
    case funk = "Funk"
    case sosumi = "Sosumi"
    case basso = "Basso"
    case pop = "Pop"
    
    var id: String { rawValue }
    
    /// The system sound name used by macOS.
    var systemSoundName: String {
        switch self {
        case .hero: return "Hero"
        case .submarine: return "Submarine"
        case .blow: return "Blow"
        case .frog: return "Frog"
        case .funk: return "Funk"
        case .sosumi: return "Sosumi"
        case .basso: return "Basso"
        case .pop: return "Pop"
        }
    }
}

// MARK: - Settings

/// Application settings stored in UserDefaults.
struct Settings: Codable, Equatable {
    /// The keyboard shortcut for screenshot capture.
    var hotkey: HotkeyConfiguration
    
    /// The keyboard shortcut for window capture.
    var tabCaptureHotkey: HotkeyConfiguration
    
    /// Whether to show the app icon in the Dock.
    var showDockIcon: Bool
    
    /// Whether to automatically copy captures to clipboard.
    var copyToClipboard: Bool
    
    /// Whether sound effects are enabled.
    var soundEffectsEnabled: Bool
    
    /// Volume level for sound effects (0.0 to 1.0).
    var soundEffectsVolume: Double
    
    /// The sound to play when capturing.
    var captureSound: CaptureSound
    
    /// Default settings configuration.
    static let `default` = Settings(
        hotkey: .default,
        tabCaptureHotkey: HotkeyConfiguration(keyCode: 17, modifiers: [.option, .shift]), // Option+Shift+T
        showDockIcon: true,
        copyToClipboard: true,
        soundEffectsEnabled: true,
        soundEffectsVolume: 0.5,
        captureSound: .frog
    )
    
    private static let settingsKey = "Settings"
    
    /// The current application settings.
    /// Reading loads from UserDefaults, writing saves to UserDefaults.
    static var current: Settings {
        get {
            if let data = UserDefaults.standard.data(forKey: settingsKey),
               let settings = try? JSONDecoder().decode(Settings.self, from: data) {
                return settings
            }
            return .default
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: settingsKey)
                NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
            }
        }
    }
}

// MARK: - Hotkey Configuration

/// Configuration for a keyboard shortcut.
struct HotkeyConfiguration: Codable, Equatable {
    /// The key code of the main key.
    var keyCode: UInt16
    
    /// The modifier keys required.
    var modifiers: NSEvent.ModifierFlags
    
    /// Default hotkey: Option+Shift+4.
    static let `default` = HotkeyConfiguration(keyCode: 21, modifiers: [.option, .shift])
    
    var modifierFlagsRaw: UInt {
        return modifiers.rawValue
    }
    
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let rawModifiers = try container.decode(UInt.self, forKey: .modifierFlagsRaw)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifierFlagsRaw, forKey: .modifierFlagsRaw)
    }
    
    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifierFlagsRaw
    }
    
    /// Checks if a keyboard event matches this hotkey configuration.
    /// - Parameter event: The keyboard event to check.
    /// - Returns: `true` if the event matches this hotkey.
    func matches(event: NSEvent) -> Bool {
        let eventModifiers = event.modifierFlags
        let allowedShortcutModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let requiredModifiers = modifiers.intersection(allowedShortcutModifiers)
        
        guard eventModifiers.contains(requiredModifiers) else {
            return false
        }
        
        let allowedModifiers: NSEvent.ModifierFlags = [.option, .shift, .command, .control, .capsLock, .numericPad]
        let eventOnlyModifiers = eventModifiers.intersection(allowedModifiers).intersection(allowedShortcutModifiers)
        
        return event.keyCode == keyCode && eventOnlyModifiers == requiredModifiers
    }
    
    /// A human-readable string representation of the hotkey.
    var displayString: String {
        var parts: [String] = []
        
        if modifiers.contains(.command) {
            parts.append("⌘")
        }
        if modifiers.contains(.option) {
            parts.append("⌥")
        }
        if modifiers.contains(.control) {
            parts.append("⌃")
        }
        if modifiers.contains(.shift) {
            parts.append("⇧")
        }
        
        parts.append(Self.displayName(for: keyCode))
        
        return parts.joined(separator: " ")
    }
    
    /// Returns the display name for a key code.
    /// - Parameter keyCode: The key code to convert.
    /// - Returns: A human-readable key name.
    static func displayName(for keyCode: UInt16) -> String {
        if let name = translateKeyCodeWithCurrentLayout(keyCode) {
            return name
        }
 
        let fallback: [UInt16: String] = [
            28: "↩", 36: "↩",
            30: "Tab", 48: "Tab",
            31: "Space", 49: "Space",
            37: "⌫", 51: "⌫",
            38: "⌦", 117: "⌦",
            40: "Esc", 53: "⎋",
            114: "Help", 115: "Home", 116: "Page Up", 119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16"
        ]
 
        return fallback[keyCode] ?? "Key \(keyCode)"
    }
 
    private static func translateKeyCodeWithCurrentLayout(_ keyCode: UInt16) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let rawLayoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
 
        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self)
        guard let layoutBytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(layoutBytes).assumingMemoryBound(to: UCKeyboardLayout.self)
 
        var deadKeyState: UInt32 = 0
        var unicodeString = [UniChar](repeating: 0, count: 8)
        var actualLength: Int = 0
 
        let modifierKeyState: UInt32 = 0
        let keyboardType = UInt32(LMGetKbdType())
 
        let err = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            modifierKeyState,
            keyboardType,
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            unicodeString.count,
            &actualLength,
            &unicodeString
        )
 
        guard err == noErr, actualLength > 0 else { return nil }
 
        let str = String(utf16CodeUnits: unicodeString, count: actualLength)
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
 
        return trimmed.uppercased()
    }
}
