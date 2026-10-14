import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - App-wide Notifications

extension Notification.Name {
    /// Posted (on the main thread) every time `AppSettings.current` is written.
    /// Observers should re-read `AppSettings.current` and re-apply whatever they own
    /// (hotkeys, Dock icon visibility, ...).
    static let settingsDidChange = Notification.Name("ClickeSettingsDidChange")

    /// Posted when a shortcut recorder starts listening for a new key combination.
    /// Global hotkeys must be suspended so the combination being typed doesn't trigger a capture.
    static let hotkeyRecordingDidBegin = Notification.Name("ClickeHotkeyRecordingDidBegin")

    /// Posted when a shortcut recorder stops listening (recorded, cancelled or dismissed).
    static let hotkeyRecordingDidEnd = Notification.Name("ClickeHotkeyRecordingDidEnd")
}

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

    /// The system sound name used by macOS (`/System/Library/Sounds/<name>.aiff`).
    var systemSoundName: String { rawValue }
}

// MARK: - After Capture Action

/// What happens right after a capture succeeds.
enum AfterCaptureAction: String, Codable, CaseIterable, Identifiable {
    /// Show the floating capture preview with quick actions (edit, copy, save, drag out).
    case showPreview
    /// Open the capture straight in the editor.
    case openEditor
    /// Do nothing visible (the capture is still copied / saved according to the other settings).
    case nothing

    var id: String { rawValue }
}

// MARK: - Settings

/// Application settings stored in UserDefaults.
///
/// Decoding is tolerant: any missing key falls back to its default value, so adding
/// a new setting never wipes the user's existing preferences.
struct AppSettings: Codable, Equatable {
    /// Shortcut for interactive area capture. `nil` = disabled.
    var areaHotkey: HotkeyConfiguration?

    /// Shortcut for window capture. `nil` = disabled.
    var windowHotkey: HotkeyConfiguration?

    /// Shortcut for full screen capture (screen under the mouse). `nil` = disabled.
    var fullScreenHotkey: HotkeyConfiguration?

    /// Whether to show the app icon in the Dock.
    var showDockIcon: Bool

    /// Whether to copy each capture to the clipboard.
    var copyToClipboard: Bool

    /// What happens after a capture.
    var afterCaptureAction: AfterCaptureAction

    /// Whether to automatically save each capture as a PNG file.
    var autoSaveCaptures: Bool

    /// Folder used for auto-saved captures. `nil` = the user's Desktop.
    var saveDirectoryPath: String?

    /// Whether sound effects are enabled.
    var soundEffectsEnabled: Bool

    /// Volume level for sound effects (0.0 to 1.0).
    var soundEffectsVolume: Double

    /// The sound to play when capturing.
    var captureSound: CaptureSound

    // MARK: Defaults

    static let defaultAreaHotkey = HotkeyConfiguration(keyCode: UInt16(kVK_ANSI_4), modifiers: [.option, .shift])
    static let defaultWindowHotkey = HotkeyConfiguration(keyCode: UInt16(kVK_ANSI_T), modifiers: [.option, .shift])
    static let defaultFullScreenHotkey = HotkeyConfiguration(keyCode: UInt16(kVK_ANSI_3), modifiers: [.option, .shift])

    /// Default settings configuration.
    static let `default` = AppSettings(
        areaHotkey: defaultAreaHotkey,
        windowHotkey: defaultWindowHotkey,
        fullScreenHotkey: defaultFullScreenHotkey,
        showDockIcon: true,
        copyToClipboard: true,
        afterCaptureAction: .showPreview,
        autoSaveCaptures: false,
        saveDirectoryPath: nil,
        soundEffectsEnabled: true,
        soundEffectsVolume: 0.5,
        captureSound: .frog
    )

    /// The resolved folder for saved captures (falls back to the Desktop).
    var saveDirectoryURL: URL {
        if let path = saveDirectoryPath, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    // MARK: Persistence

    private static let settingsKey = "Settings"

    /// The current application settings.
    /// Reading loads from UserDefaults, writing saves to UserDefaults and posts `.settingsDidChange`.
    static var current: AppSettings {
        get {
            if let data = UserDefaults.standard.data(forKey: settingsKey),
               let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
                return settings
            }
            return .default
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: settingsKey)
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        }
    }

    // MARK: Codable (backward compatible)

    // Raw values of the first three keys are kept from v1.x so existing preferences survive.
    private enum CodingKeys: String, CodingKey {
        case areaHotkey = "hotkey"
        case windowHotkey = "tabCaptureHotkey"
        case fullScreenHotkey
        case showDockIcon
        case copyToClipboard
        case afterCaptureAction
        case autoSaveCaptures
        case saveDirectoryPath
        case soundEffectsEnabled
        case soundEffectsVolume
        case captureSound
    }

    init(
        areaHotkey: HotkeyConfiguration?,
        windowHotkey: HotkeyConfiguration?,
        fullScreenHotkey: HotkeyConfiguration?,
        showDockIcon: Bool,
        copyToClipboard: Bool,
        afterCaptureAction: AfterCaptureAction,
        autoSaveCaptures: Bool,
        saveDirectoryPath: String?,
        soundEffectsEnabled: Bool,
        soundEffectsVolume: Double,
        captureSound: CaptureSound
    ) {
        self.areaHotkey = areaHotkey
        self.windowHotkey = windowHotkey
        self.fullScreenHotkey = fullScreenHotkey
        self.showDockIcon = showDockIcon
        self.copyToClipboard = copyToClipboard
        self.afterCaptureAction = afterCaptureAction
        self.autoSaveCaptures = autoSaveCaptures
        self.saveDirectoryPath = saveDirectoryPath
        self.soundEffectsEnabled = soundEffectsEnabled
        self.soundEffectsVolume = soundEffectsVolume
        self.captureSound = captureSound
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default

        /// A key that is present but `null` means "disabled"; a missing key means "use the default".
        func hotkey(_ key: CodingKeys, default value: HotkeyConfiguration?) -> HotkeyConfiguration? {
            guard c.contains(key) else { return value }
            if (try? c.decodeNil(forKey: key)) == true { return nil }
            return (try? c.decode(HotkeyConfiguration.self, forKey: key)) ?? value
        }

        areaHotkey = hotkey(.areaHotkey, default: d.areaHotkey)
        windowHotkey = hotkey(.windowHotkey, default: d.windowHotkey)
        fullScreenHotkey = hotkey(.fullScreenHotkey, default: d.fullScreenHotkey)
        showDockIcon = (try? c.decodeIfPresent(Bool.self, forKey: .showDockIcon)) ?? d.showDockIcon
        copyToClipboard = (try? c.decodeIfPresent(Bool.self, forKey: .copyToClipboard)) ?? d.copyToClipboard
        afterCaptureAction = (try? c.decodeIfPresent(AfterCaptureAction.self, forKey: .afterCaptureAction)) ?? d.afterCaptureAction
        autoSaveCaptures = (try? c.decodeIfPresent(Bool.self, forKey: .autoSaveCaptures)) ?? d.autoSaveCaptures
        saveDirectoryPath = try? c.decodeIfPresent(String.self, forKey: .saveDirectoryPath)
        soundEffectsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .soundEffectsEnabled)) ?? d.soundEffectsEnabled
        soundEffectsVolume = (try? c.decodeIfPresent(Double.self, forKey: .soundEffectsVolume)) ?? d.soundEffectsVolume
        captureSound = (try? c.decodeIfPresent(CaptureSound.self, forKey: .captureSound)) ?? d.captureSound
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Hotkeys are always written (explicit null when disabled) so "disabled" survives a reload.
        try c.encode(areaHotkey, forKey: .areaHotkey)
        try c.encode(windowHotkey, forKey: .windowHotkey)
        try c.encode(fullScreenHotkey, forKey: .fullScreenHotkey)
        try c.encode(showDockIcon, forKey: .showDockIcon)
        try c.encode(copyToClipboard, forKey: .copyToClipboard)
        try c.encode(afterCaptureAction, forKey: .afterCaptureAction)
        try c.encode(autoSaveCaptures, forKey: .autoSaveCaptures)
        try c.encodeIfPresent(saveDirectoryPath, forKey: .saveDirectoryPath)
        try c.encode(soundEffectsEnabled, forKey: .soundEffectsEnabled)
        try c.encode(soundEffectsVolume, forKey: .soundEffectsVolume)
        try c.encode(captureSound, forKey: .captureSound)
    }
}

// MARK: - Hotkey Configuration

/// Configuration for a keyboard shortcut (virtual key code + modifier flags).
struct HotkeyConfiguration: Codable, Equatable, Hashable {
    /// The virtual key code of the main key (`kVK_*`). Note: 0 is a real key (`kVK_ANSI_A`).
    var keyCode: UInt16

    /// The modifier keys required (only ⌘ ⌥ ⌃ ⇧ are meaningful).
    var modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.supportedModifiers)
    }

    /// The modifier flags a shortcut can use.
    static let supportedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifierFlagsRaw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let rawModifiers = try container.decode(UInt.self, forKey: .modifierFlagsRaw)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers).intersection(Self.supportedModifiers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifierFlagsRaw)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    // MARK: Carbon

    /// Modifier mask for Carbon's `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    // MARK: Display

    /// A human-readable representation, e.g. "⌥⇧4" (macOS order: ⌃ ⌥ ⇧ ⌘).
    var displayString: String {
        modifierSymbols.joined() + Self.displayName(for: keyCode)
    }

    /// Modifier symbols in the standard macOS order (⌃ ⌥ ⇧ ⌘).
    var modifierSymbols: [String] {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        return parts
    }

    /// Returns the display name for a key code, using the current keyboard layout when possible.
    static func displayName(for keyCode: UInt16) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "Space",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
            kVK_Help: "Help", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
        ]
        if let name = special[Int(keyCode)] { return name }
        if let name = translateKeyCodeWithCurrentLayout(keyCode) { return name }
        return "Key \(keyCode)"
    }

    /// Whether the key is a function key (F1–F20), which may be used without modifiers.
    var isFunctionKey: Bool {
        let fKeys: Set<Int> = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        return fKeys.contains(Int(keyCode))
    }

    /// A global shortcut must use ⌘, ⌥ or ⌃ (⇧ alone would hijack normal typing), unless it's an F-key.
    var isValidGlobalShortcut: Bool {
        isFunctionKey || !modifiers.intersection([.command, .option, .control]).isEmpty
    }

    private static func translateKeyCodeWithCurrentLayout(_ keyCode: UInt16) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue()
        guard let layoutBytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(layoutBytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        var deadKeyState: UInt32 = 0
        var unicodeString = [UniChar](repeating: 0, count: 8)
        var actualLength = 0

        let err = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            unicodeString.count,
            &actualLength,
            &unicodeString
        )

        guard err == noErr, actualLength > 0 else { return nil }

        let str = String(utf16CodeUnits: unicodeString, count: actualLength)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return str.isEmpty ? nil : str.uppercased()
    }
}
