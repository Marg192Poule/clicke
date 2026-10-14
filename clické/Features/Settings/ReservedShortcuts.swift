import AppKit
import Carbon.HIToolbox

// MARK: - Reserved Shortcuts

/// Why a shortcut is already taken by macOS or by apps in general.
enum ReservedShortcutUsage: Equatable {
    /// A well-known macOS shortcut. `purpose` completes "macOS uses ⌘⇧4 to …".
    case known(purpose: String)
    /// Another shortcut enabled in System Settings › Keyboard › Keyboard Shortcuts.
    case system
    /// A ⌘-only combination, which apps use for their menu commands.
    case appCommand
}

extension HotkeyConfiguration {
    /// What macOS (or apps in general) already use this shortcut for, or `nil` if it looks free.
    ///
    /// System-wide shortcuts the user turned off in System Settings are not reported.
    var reservedUsage: ReservedShortcutUsage? {
        let systemShortcuts = Self.enabledSystemShortcuts()

        if let known = ReservedShortcut.wellKnown.first(where: { $0.shortcut == self }) {
            if known.canBeTurnedOff, let systemShortcuts, !systemShortcuts.contains(self) {
                return nil
            }
            return .known(purpose: known.purpose)
        }
        if systemShortcuts?.contains(self) == true {
            return .system
        }
        if modifiers == [.command] {
            return .appCommand
        }
        return nil
    }

    /// The shortcuts currently enabled in System Settings › Keyboard › Keyboard Shortcuts
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
    let shortcut: HotkeyConfiguration
    /// Completes the sentence "macOS uses ⌘⇧4 to …".
    let purpose: String
    /// Whether it's a system shortcut the user can turn off in System Settings › Keyboard › Keyboard Shortcuts.
    let canBeTurnedOff: Bool

    init(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags, _ purpose: String, canBeTurnedOff: Bool) {
        self.shortcut = HotkeyConfiguration(keyCode: UInt16(keyCode), modifiers: modifiers)
        self.purpose = purpose
        self.canBeTurnedOff = canBeTurnedOff
    }

    static let wellKnown: [ReservedShortcut] = [
        // Screenshots
        .init(kVK_ANSI_3, [.shift, .command], String(localized: "take a screenshot of the screen"), canBeTurnedOff: true),
        .init(kVK_ANSI_3, [.control, .shift, .command], String(localized: "copy a screenshot of the screen"), canBeTurnedOff: true),
        .init(kVK_ANSI_4, [.shift, .command], String(localized: "take a screenshot of an area"), canBeTurnedOff: true),
        .init(kVK_ANSI_4, [.control, .shift, .command], String(localized: "copy a screenshot of an area"), canBeTurnedOff: true),
        .init(kVK_ANSI_5, [.shift, .command], String(localized: "show the screenshot and recording options"), canBeTurnedOff: true),
        .init(kVK_ANSI_6, [.shift, .command], String(localized: "take a screenshot of the Touch Bar"), canBeTurnedOff: true),
        // Spotlight & input sources
        .init(kVK_Space, [.command], String(localized: "show Spotlight"), canBeTurnedOff: true),
        .init(kVK_Space, [.option, .command], String(localized: "show the Finder search window"), canBeTurnedOff: true),
        .init(kVK_Space, [.control], String(localized: "select the previous input source"), canBeTurnedOff: true),
        .init(kVK_Space, [.control, .option], String(localized: "select the next input source"), canBeTurnedOff: true),
        .init(kVK_ANSI_Grave, [.command], String(localized: "move the focus to the next window"), canBeTurnedOff: true),
        // App switching and standard commands
        .init(kVK_Tab, [.command], String(localized: "switch between apps"), canBeTurnedOff: false),
        .init(kVK_Tab, [.shift, .command], String(localized: "switch between apps"), canBeTurnedOff: false),
        .init(kVK_ANSI_Q, [.command], String(localized: "quit apps"), canBeTurnedOff: false),
        .init(kVK_ANSI_W, [.command], String(localized: "close windows"), canBeTurnedOff: false),
        .init(kVK_ANSI_H, [.command], String(localized: "hide apps"), canBeTurnedOff: false),
        .init(kVK_ANSI_H, [.option, .command], String(localized: "hide other apps"), canBeTurnedOff: false),
        .init(kVK_ANSI_M, [.command], String(localized: "minimize windows"), canBeTurnedOff: false),
        .init(kVK_Escape, [.option, .command], String(localized: "force quit apps"), canBeTurnedOff: false),
        .init(kVK_ANSI_Q, [.control, .command], String(localized: "lock the screen"), canBeTurnedOff: false),
        .init(kVK_ANSI_F, [.control, .command], String(localized: "enter full screen"), canBeTurnedOff: false),
        .init(kVK_Space, [.control, .command], String(localized: "show emoji and symbols"), canBeTurnedOff: false),
    ]
}
