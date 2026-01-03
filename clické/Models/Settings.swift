import Foundation
import AppKit
import Carbon.HIToolbox

struct Settings: Codable, Equatable {
    var hotkey: HotkeyConfiguration
    var tabCaptureHotkey: HotkeyConfiguration
    
    var showDockIcon: Bool
    var copyToClipboard: Bool
    
    var soundEffectsEnabled: Bool
    var soundEffectsVolume: Double
    
    var saveHistory: Bool
    var maxHistoryEntries: Int?
    
    static let `default` = Settings(
        hotkey: .default,
        tabCaptureHotkey: HotkeyConfiguration(keyCode: 17, modifiers: [.option, .shift]), // Option+Shift+T
        showDockIcon: true,  // Temporairement true pour tester l'icône
        copyToClipboard: true,
        soundEffectsEnabled: true,
        soundEffectsVolume: 0.5,
        saveHistory: true,
        maxHistoryEntries: 100
    )
    
    private static let settingsKey = "Settings"
    
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


struct HotkeyConfiguration: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    
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
