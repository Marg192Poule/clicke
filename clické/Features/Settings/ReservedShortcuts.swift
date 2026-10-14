import AppKit
import Carbon.HIToolbox

// MARK: - Reserved Shortcuts

/// Why a shortcut is already taken by macOS or by apps in general.
enum ReservedShortcutUsage: Equatable {
    /// A macOS screenshot shortcut (⌘⇧3, ⌘⇧4, ⌘⇧5…), which the user may deliberately hand over to
    /// Clické. `purpose` completes "macOS uses ⌘⇧4 to …".
    case screenshot(purpose: String)
    /// Another well-known macOS shortcut (⌘Q, ⌘W, ⌘H, ⌘Tab, ⌘Space…). A global shortcut would break
    /// it in every app. `purpose` completes "macOS uses ⌘Q to …".
    case known(purpose: String)
    /// Another shortcut enabled in System Settings > Keyboard > Keyboard Shortcuts.
    case system
    /// A ⌘-only combination, which apps use for their menu commands.
    case appCommand

    /// Whether the user may save the shortcut anyway: only the macOS screenshot shortcuts.
    var canBeUsedAnyway: Bool {
        if case .screenshot = self { true } else { false }
    }
}

extension HotkeyConfiguration {
    /// What macOS (or apps in general) already use this shortcut for, or `nil` if it looks free.
    ///
    /// System-wide shortcuts the user turned off in System Settings are not reported.
    var reservedUsage: ReservedShortcutUsage? {
        let systemShortcuts = Self.enabledSystemShortcuts()

        if let known = ReservedShortcut.wellKnown.first(where: { $0.matches(self) }) {
            if known.canBeTurnedOff, let systemShortcuts, !systemShortcuts.contains(self) {
                return nil
            }
            return known.isScreenshot ? .screenshot(purpose: known.purpose) : .known(purpose: known.purpose)
        }
        if systemShortcuts?.contains(self) == true {
            return .system
        }
        if modifiers == [.command] {
            return .appCommand
        }
        return nil
    }

    /// The shortcuts currently enabled in System Settings > Keyboard > Keyboard Shortcuts
    /// ("symbolic hot keys"), or `nil` if they can't be read.
    private static func enabledSystemShortcuts() -> Set<HotkeyConfiguration>? {
        var unmanagedEntries: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanagedEntries) == noErr,
              let entries = unmanagedEntries?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }

        var shortcuts = Set<HotkeyConfiguration>()
        for entry in entries {
            guard (entry[kHISymbolicHotKeyEnabled] as? Bool) == true,
                  let keyCode = entry[kHISymbolicHotKeyCode] as? Int,
                  let carbonModifiers = entry[kHISymbolicHotKeyModifiers] as? Int,
                  let keyCode = UInt16(exactly: keyCode) else {
                continue
            }
            var modifiers: NSEvent.ModifierFlags = []
            if carbonModifiers & cmdKey != 0 { modifiers.insert(.command) }
            if carbonModifiers & optionKey != 0 { modifiers.insert(.option) }
            if carbonModifiers & controlKey != 0 { modifiers.insert(.control) }
            if carbonModifiers & shiftKey != 0 { modifiers.insert(.shift) }
            shortcuts.insert(HotkeyConfiguration(keyCode: keyCode, modifiers: modifiers))
        }
        return shortcuts
    }
}

/// A shortcut macOS is known to use.
private struct ReservedShortcut {
    enum Key {
        /// A physical key (system shortcuts such as ⌘⇧4 or ⌘Space).
        case code(Int)
        /// The letter a key types in the current layout (menu commands such as ⌘Q, which is on a
        /// different key with AZERTY).
        case letter(String)
    }

    let key: Key
    let modifiers: NSEvent.ModifierFlags
    /// Completes the sentence "macOS uses ⌘⇧4 to …".
    let purpose: String
    /// Whether it's a system shortcut the user can turn off in System Settings > Keyboard > Keyboard Shortcuts.
    let canBeTurnedOff: Bool
    /// Whether it's a macOS screenshot shortcut, which a screenshot app may take over.
    let isScreenshot: Bool

    init(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags, _ purpose: String, canBeTurnedOff: Bool, isScreenshot: Bool = false) {
        self.key = .code(keyCode)
        self.modifiers = modifiers
        self.purpose = purpose
        self.canBeTurnedOff = canBeTurnedOff
        self.isScreenshot = isScreenshot
    }

    /// A menu command, matched by the letter typed in the current layout (it can't be turned off).
    init(_ letter: String, _ modifiers: NSEvent.ModifierFlags, _ purpose: String) {
        self.key = .letter(letter)
        self.modifiers = modifiers
        self.purpose = purpose
        self.canBeTurnedOff = false
        self.isScreenshot = false
    }

    /// A macOS screenshot shortcut (they can all be turned off in System Settings).
    static func screenshot(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags, _ purpose: String) -> ReservedShortcut {
        ReservedShortcut(keyCode, modifiers, purpose, canBeTurnedOff: true, isScreenshot: true)
    }

    func matches(_ shortcut: HotkeyConfiguration) -> Bool {
        guard shortcut.modifiers == modifiers else { return false }
        switch key {
        case .code(let keyCode):
            return Int(shortcut.keyCode) == keyCode
        case .letter(let letter):
            return HotkeyConfiguration.displayName(for: shortcut.keyCode) == letter
        }
    }

    static let wellKnown: [ReservedShortcut] = [
        // Screenshots
        .screenshot(kVK_ANSI_3, [.shift, .command], String(localized: "take a screenshot of the screen")),
        .screenshot(kVK_ANSI_3, [.control, .shift, .command], String(localized: "copy a screenshot of the screen")),
        .screenshot(kVK_ANSI_4, [.shift, .command], String(localized: "take a screenshot of an area")),
        .screenshot(kVK_ANSI_4, [.control, .shift, .command], String(localized: "copy a screenshot of an area")),
        .screenshot(kVK_ANSI_5, [.shift, .command], String(localized: "show the screenshot and recording options")),
        .screenshot(kVK_ANSI_6, [.shift, .command], String(localized: "take a screenshot of the Touch Bar")),
        // Spotlight & input sources
        .init(kVK_Space, [.command], String(localized: "show Spotlight"), canBeTurnedOff: true),
        .init(kVK_Space, [.option, .command], String(localized: "show the Finder search window"), canBeTurnedOff: true),
        .init(kVK_Space, [.control], String(localized: "select the previous input source"), canBeTurnedOff: true),
        .init(kVK_Space, [.control, .option], String(localized: "select the next input source"), canBeTurnedOff: true),
        .init(kVK_ANSI_Grave, [.command], String(localized: "move the focus to the next window"), canBeTurnedOff: true),
        // App switching and standard commands
        .init(kVK_Tab, [.command], String(localized: "switch between apps"), canBeTurnedOff: false),
        .init(kVK_Tab, [.shift, .command], String(localized: "switch between apps"), canBeTurnedOff: false),
        .init("Q", [.command], String(localized: "quit apps")),
        .init("W", [.command], String(localized: "close windows")),
        .init("H", [.command], String(localized: "hide apps")),
        .init("H", [.option, .command], String(localized: "hide other apps")),
        .init("M", [.command], String(localized: "minimize windows")),
        .init(kVK_Escape, [.option, .command], String(localized: "force quit apps"), canBeTurnedOff: false),
        .init("Q", [.control, .command], String(localized: "lock the screen")),
        .init("F", [.control, .command], String(localized: "enter full screen")),
        .init(kVK_Space, [.control, .command], String(localized: "show emoji and symbols"), canBeTurnedOff: false),
    ]
}
