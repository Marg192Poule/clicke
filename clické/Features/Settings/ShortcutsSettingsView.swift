import SwiftUI
import AppKit

// MARK: - Shortcut Actions

/// The captures that can be triggered by a global shortcut.
enum ShortcutAction: CaseIterable, Identifiable {
    case area
    case window
    case fullScreen

    var id: Self { self }

    var title: String {
        switch self {
        case .area: String(localized: "Capture Area")
        case .window: String(localized: "Capture Window")
        case .fullScreen: String(localized: "Capture Full Screen")
        }
    }

    var keyPath: WritableKeyPath<AppSettings, HotkeyConfiguration?> {
        switch self {
        case .area: \.areaHotkey
        case .window: \.windowHotkey
        case .fullScreen: \.fullScreenHotkey
        }
    }

    var defaultShortcut: HotkeyConfiguration {
        switch self {
        case .area: AppSettings.defaultAreaHotkey
        case .window: AppSettings.defaultWindowHotkey
        case .fullScreen: AppSettings.defaultFullScreenHotkey
        }
    }
}

// MARK: - Shortcut Issues

/// Why a recorded shortcut wasn't saved.
enum ShortcutIssue: Equatable {
    /// Not usable as a global shortcut (needs ⌘, ⌥ or ⌃, unless it's a function key).
    case invalid(HotkeyConfiguration)
    /// Already assigned to another capture.
    case conflict(HotkeyConfiguration, with: ShortcutAction)
    /// Used by macOS or apps; can be saved anyway after confirmation.
    case reserved(HotkeyConfiguration, ReservedShortcutUsage)
}

// MARK: - Shortcuts Settings

/// Shortcuts tab: one recorder per capture type, inline validation and "Restore Defaults".
struct ShortcutsSettingsView: View {
    @Bindable var model: SettingsModel

    /// Inline message per row, cleared when that row records again.
    @State private var issues: [ShortcutAction: ShortcutIssue] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutRow(
                        action: action,
                        shortcut: model.settings[keyPath: action.keyPath],
                        issue: issues[action],
                        onRecordingStarted: { issues[action] = nil },
                        onRecord: { record($0, for: action) },
                        onClear: { save(nil, for: action) },
                        onReject: { issues[action] = .invalid($0) },
                        onUseAnyway: { useAnyway(for: action) }
                    )
                }
            } footer: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Click a shortcut, then type the new key combination. Press Delete to turn it off, or Escape to cancel.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Restore Defaults", action: restoreDefaults)
                        .disabled(usesDefaultShortcuts && issues.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private var usesDefaultShortcuts: Bool {
        ShortcutAction.allCases.allSatisfy { model.settings[keyPath: $0.keyPath] == $0.defaultShortcut }
    }

    // MARK: Actions

    private func record(_ shortcut: HotkeyConfiguration, for action: ShortcutAction) {
        // Typing the current shortcut again is a no-op.
        if model.settings[keyPath: action.keyPath] == shortcut {
            issues[action] = nil
            return
        }
        if let other = conflictingAction(for: shortcut, excluding: action) {
            NSSound.beep()
            issues[action] = .conflict(shortcut, with: other)
            return
        }
        if let usage = shortcut.reservedUsage {
            issues[action] = .reserved(shortcut, usage)
            return
        }
        save(shortcut, for: action)
    }

    private func useAnyway(for action: ShortcutAction) {
        guard case .reserved(let shortcut, _) = issues[action] else { return }
        if let other = conflictingAction(for: shortcut, excluding: action) {
            issues[action] = .conflict(shortcut, with: other)
            return
        }
        save(shortcut, for: action)
    }

    private func save(_ shortcut: HotkeyConfiguration?, for action: ShortcutAction) {
        issues[action] = nil
        model.settings[keyPath: action.keyPath] = shortcut
    }

    private func restoreDefaults() {
        var settings = model.settings
        for action in ShortcutAction.allCases {
            settings[keyPath: action.keyPath] = action.defaultShortcut
        }
        model.settings = settings
        issues = [:]
    }

    private func conflictingAction(for shortcut: HotkeyConfiguration, excluding action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { other in
            other != action && model.settings[keyPath: other.keyPath] == shortcut
        }
    }
}

// MARK: - Shortcut Row

/// "Capture Area   [⌥⇧4 ⓧ]", with an inline message under it when the last recording was refused.
private struct ShortcutRow: View {
    let action: ShortcutAction
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
                Text(action.title)
                Spacer()
                ShortcutRecorder(
                    shortcut: shortcut,
                    title: action.title,
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

            if case .reserved = issue {
                Button("Use Anyway", action: onUseAnyway)
                    .controlSize(.small)
            }
        }
    }

    private var symbolName: String {
        switch issue {
        case .invalid: "xmark.octagon.fill"
        case .conflict, .reserved: "exclamationmark.triangle.fill"
        }
    }

    private var message: Text {
        switch issue {
        case .invalid(let shortcut):
            return Text("\(shortcut.displayString) can’t be used. Include ⌘, ⌥ or ⌃, or use a function key.")
        case .conflict(let shortcut, let other):
            return Text("\(shortcut.displayString) is already used for “\(other.title)”.")
        case .reserved(let shortcut, .known(let purpose)):
            return Text("macOS uses \(shortcut.displayString) to \(purpose).")
        case .reserved(let shortcut, .system):
            return Text("\(shortcut.displayString) is used by macOS. You can turn it off in System Settings › Keyboard › Keyboard Shortcuts.")
        case .reserved(let shortcut, .appCommand):
            return Text("Apps use \(shortcut.displayString) for menu commands. Using it here would override it in every app.")
        }
    }
}
