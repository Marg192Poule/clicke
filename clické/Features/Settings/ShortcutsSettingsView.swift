import SwiftUI
import AppKit

// MARK: - Capture Mode Shortcuts

private extension CaptureMode {
    /// Where this mode's shortcut is stored.
    var hotkeyKeyPath: WritableKeyPath<AppSettings, HotkeyConfiguration?> {
        switch self {
        case .area: \.areaHotkey
        case .window: \.windowHotkey
        case .fullScreen: \.fullScreenHotkey
        }
    }

    var defaultHotkey: HotkeyConfiguration {
        switch self {
        case .area: AppSettings.defaultAreaHotkey
        case .window: AppSettings.defaultWindowHotkey
        case .fullScreen: AppSettings.defaultFullScreenHotkey
        }
    }
}

// MARK: - Shortcut Issues

/// Why a shortcut wasn't saved, or why a saved shortcut doesn't work.
enum ShortcutIssue: Equatable {
    /// Not usable as a global shortcut (needs ⌘, ⌥ or ⌃, unless it's a function key).
    case invalid(HotkeyConfiguration)
    /// Already assigned to another capture.
    case conflict(HotkeyConfiguration, with: CaptureMode)
    /// Used by macOS or apps. Only macOS screenshot shortcuts can be saved anyway.
    case reserved(HotkeyConfiguration, ReservedShortcutUsage)
    /// Saved, but not active: another app already uses it (see `HotkeyAvailability`).
    case unavailable(HotkeyConfiguration)
}

// MARK: - Shortcuts Settings

/// Shortcuts tab: one recorder per capture type, inline validation and "Restore Defaults".
///
/// Each row shows, in order of priority, why its last recording was refused, or what's wrong with
/// its saved shortcut (invalid or duplicated, e.g. from older settings, or not active).
struct ShortcutsSettingsView: View {
    @Bindable var model: SettingsModel

    /// Why the last recording of a row wasn't saved, cleared when that row records again.
    @State private var recordingIssues: [CaptureMode: ShortcutIssue] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    ShortcutRow(
                        title: mode.title,
                        shortcut: model.settings[keyPath: mode.hotkeyKeyPath],
                        issue: recordingIssues[mode] ?? savedShortcutIssue(for: mode),
                        onRecordingStarted: { recordingIssues[mode] = nil },
                        onRecord: { record($0, for: mode) },
                        onClear: { save(nil, for: mode) },
                        onReject: { recordingIssues[mode] = .invalid($0) },
                        onUseAnyway: { useAnyway(for: mode) }
                    )
                }
            } footer: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Click a shortcut, then type the new key combination. Press Delete to turn it off, or Escape to cancel.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Restore Defaults", action: restoreDefaults)
                        .disabled(usesDefaultShortcuts && recordingIssues.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private var usesDefaultShortcuts: Bool {
        CaptureMode.allCases.allSatisfy { model.settings[keyPath: $0.hotkeyKeyPath] == $0.defaultHotkey }
    }

    /// What's wrong with the shortcut saved for `mode`, if anything.
    private func savedShortcutIssue(for mode: CaptureMode) -> ShortcutIssue? {
        guard let shortcut = model.settings[keyPath: mode.hotkeyKeyPath] else { return nil }

        // Settings from older versions may contain shortcuts that can't be registered (e.g. ⇧ only).
        if !shortcut.isValidGlobalShortcut {
            return .invalid(shortcut)
        }
        // A duplicated shortcut works for the first capture only (it's registered first).
        let earlierModes = CaptureMode.allCases.prefix { $0 != mode }
        if let other = earlierModes.first(where: { model.settings[keyPath: $0.hotkeyKeyPath] == shortcut }) {
            return .conflict(shortcut, with: other)
        }
        if model.unavailableHotkeys.contains(shortcut) {
            return .unavailable(shortcut)
        }
        return nil
    }

    // MARK: Actions

    private func record(_ shortcut: HotkeyConfiguration, for mode: CaptureMode) {
        // Typing the current shortcut again is a no-op.
        if model.settings[keyPath: mode.hotkeyKeyPath] == shortcut {
            recordingIssues[mode] = nil
            return
        }
        if let other = conflictingMode(for: shortcut, excluding: mode) {
            NSSound.beep()
            recordingIssues[mode] = .conflict(shortcut, with: other)
            return
        }
        if let usage = shortcut.reservedUsage {
            if !usage.canBeUsedAnyway {
                NSSound.beep()
            }
            recordingIssues[mode] = .reserved(shortcut, usage)
            return
        }
        save(shortcut, for: mode)
    }

    private func useAnyway(for mode: CaptureMode) {
        guard case .reserved(let shortcut, let usage) = recordingIssues[mode], usage.canBeUsedAnyway else { return }
        if let other = conflictingMode(for: shortcut, excluding: mode) {
            recordingIssues[mode] = .conflict(shortcut, with: other)
            return
        }
        save(shortcut, for: mode)
    }

    private func save(_ shortcut: HotkeyConfiguration?, for mode: CaptureMode) {
        recordingIssues[mode] = nil
        model.settings[keyPath: mode.hotkeyKeyPath] = shortcut
    }

    private func restoreDefaults() {
        var settings = model.settings
        for mode in CaptureMode.allCases {
            settings[keyPath: mode.hotkeyKeyPath] = mode.defaultHotkey
        }
        model.settings = settings
        recordingIssues = [:]
    }

    private func conflictingMode(for shortcut: HotkeyConfiguration, excluding mode: CaptureMode) -> CaptureMode? {
        CaptureMode.allCases.first { other in
            other != mode && model.settings[keyPath: other.hotkeyKeyPath] == shortcut
        }
    }
}

// MARK: - Shortcut Row

/// "Capture Area   [⌥⇧4 ⓧ]", with an inline message under it when there's an issue.
private struct ShortcutRow: View {
    let title: String
    let shortcut: HotkeyConfiguration?
    let issue: ShortcutIssue?
    let onRecordingStarted: () -> Void
    let onRecord: (HotkeyConfiguration) -> Void
    let onClear: () -> Void
    let onReject: (HotkeyConfiguration) -> Void
    let onUseAnyway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                ShortcutRecorder(
                    shortcut: shortcut,
                    title: title,
                    onRecordingStarted: onRecordingStarted,
                    onRecord: onRecord,
                    onClear: onClear,
                    onReject: onReject
                )
                .fixedSize()
            }

            if let issue {
                ShortcutIssueMessage(issue: issue, onUseAnyway: onUseAnyway)
            }
        }
    }
}

// MARK: - Shortcut Issue Message

private struct ShortcutIssueMessage: View {
    let issue: ShortcutIssue
    let onUseAnyway: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.multicolor)
                .accessibilityHidden(true)

            message
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if case .reserved(_, let usage) = issue, usage.canBeUsedAnyway {
                Button("Use Anyway", action: onUseAnyway)
                    .controlSize(.small)
            }
        }
    }

    private var symbolName: String {
        switch issue {
        case .invalid: "xmark.octagon.fill"
        case .conflict, .reserved, .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var message: Text {
        switch issue {
        case .invalid(let shortcut):
            Text("\(shortcut.displayString) can’t be used. Include ⌘, ⌥ or ⌃, or use a function key.")
        case .conflict(let shortcut, let other):
            Text("\(shortcut.displayString) is already used for “\(other.title)”.")
        case .unavailable(let shortcut):
            Text("\(shortcut.displayString) is used by another app. Choose a different shortcut.")
        case .reserved(let shortcut, .screenshot(let purpose)):
            Text("macOS uses \(shortcut.displayString) to \(purpose).")
        case .reserved(let shortcut, .known(let purpose)):
            Text("macOS uses \(shortcut.displayString) to \(purpose). Choose a different shortcut.")
        case .reserved(let shortcut, .system):
            Text("\(shortcut.displayString) is used by macOS. Choose a different shortcut, or turn it off in System Settings > Keyboard > Keyboard Shortcuts.")
        case .reserved(let shortcut, .appCommand):
            Text("Apps use \(shortcut.displayString) for menu commands. Choose a different shortcut.")
        }
    }
}
