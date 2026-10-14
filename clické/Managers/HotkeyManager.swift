import AppKit
import Carbon.HIToolbox
import os

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clicke", category: "Hotkeys")

/// Four-character code identifying Clické's hot keys ('Clke').
nonisolated private let hotKeySignature: OSType = 0x436C_6B65

/// Registers the capture shortcuts as system-wide hot keys with Carbon's `RegisterEventHotKey`.
///
/// Unlike an `NSEvent` global key monitor, a registered hot key:
/// - doesn't require the Accessibility permission, and Clické never sees any other keystroke;
/// - consumes the key press, so the shortcut isn't also typed into the frontmost app.
///
/// Shortcuts are re-registered when settings change and suspended while the Settings
/// window records a new shortcut.
final class HotkeyManager: NSObject {

    // MARK: - Properties

    private let onHotkey: (CaptureMode) -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    /// The shortcuts currently registered, to skip re-registering when unrelated settings change.
    private var registeredConfigurations: [CaptureMode: HotkeyConfiguration] = [:]
    private var isRecordingShortcut = false
    private var isStarted = false

    /// Shortcuts the user was already told are taken, so the warning isn't repeated on every change.
    private var reportedConflicts: Set<HotkeyConfiguration> = []

    // MARK: - Initialization

    /// - Parameter onHotkey: Called on the main actor when a capture shortcut is pressed.
    init(onHotkey: @escaping (CaptureMode) -> Void) {
        self.onHotkey = onHotkey
        super.init()
    }

    // MARK: - Lifecycle

    /// Installs the hot key handler, registers the shortcuts from `AppSettings` and starts
    /// following settings changes.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        installEventHandler()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(settingsDidChange), name: .settingsDidChange, object: nil)
        center.addObserver(self, selector: #selector(recordingDidBegin), name: .hotkeyRecordingDidBegin, object: nil)
        center.addObserver(self, selector: #selector(recordingDidEnd), name: .hotkeyRecordingDidEnd, object: nil)

        registerHotkeys()
    }

    /// Unregisters everything.
    func stop() {
        guard isStarted else { return }
        isStarted = false

        NotificationCenter.default.removeObserver(self)
        unregisterHotkeys()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    // MARK: - Notifications

    @objc private func settingsDidChange() {
        guard !isRecordingShortcut, currentConfigurations() != registeredConfigurations else { return }
        registerHotkeys()
    }

    @objc private func recordingDidBegin() {
        isRecordingShortcut = true
        unregisterHotkeys()
    }

    @objc private func recordingDidEnd() {
        isRecordingShortcut = false
        registerHotkeys()
    }

    // MARK: - Registration

    private func currentConfigurations() -> [CaptureMode: HotkeyConfiguration] {
        let settings = AppSettings.current
        var configurations: [CaptureMode: HotkeyConfiguration] = [:]
        for mode in CaptureMode.allCases {
            configurations[mode] = mode.hotkey(in: settings)
        }
        return configurations
    }

    private func registerHotkeys() {
        unregisterHotkeys()
        guard isStarted, !isRecordingShortcut else { return }

        let configurations = currentConfigurations()
        var conflicts: [HotkeyConfiguration] = []

        for mode in CaptureMode.allCases {
            guard let configuration = configurations[mode] else { continue }   // disabled

            // A shortcut without ⌘ ⌥ ⌃ (other than an F-key) would swallow normal typing.
            guard configuration.isValidGlobalShortcut else {
                logger.warning("Not registering \(configuration.displayString, privacy: .public): not a valid global shortcut")
                continue
            }

            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(configuration.keyCode),
                configuration.carbonModifiers,
                EventHotKeyID(signature: hotKeySignature, id: mode.hotKeyID),
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                hotKeyRefs.append(hotKeyRef)
                logger.debug("Registered \(configuration.displayString, privacy: .public)")
            } else {
                // eventHotKeyExistsErr (-9878): the combination is already taken (by another app or another mode).
                logger.error("Couldn't register \(configuration.displayString, privacy: .public) (OSStatus \(status, privacy: .public))")
                conflicts.append(configuration)
            }
        }

        registeredConfigurations = configurations
        reportConflicts(conflicts)
    }

    /// Tells the user (once per shortcut) that a shortcut doesn't work because something else uses it.
    private func reportConflicts(_ conflicts: [HotkeyConfiguration]) {
        let newConflict = conflicts.first { !reportedConflicts.contains($0) }
        reportedConflicts = Set(conflicts)
        guard let newConflict else { return }
        ToastManager.shared.show(
            message: String(localized: "The shortcut \(newConflict.displayString) is already in use"),
            icon: "exclamationmark.triangle.fill",
            success: false
        )
    }

    private func unregisterHotkeys() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        registeredConfigurations = [:]
    }

    // MARK: - Event Handling

    private func installEventHandler() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            logger.error("Couldn't install the hot key handler (OSStatus \(status, privacy: .public))")
        }
    }

    /// Called on the main actor for each press of one of our hot keys.
    fileprivate func hotKeyPressed(id: UInt32) {
        guard let mode = CaptureMode(hotKeyID: id) else { return }
        onHotkey(mode)
    }
}

// MARK: - Carbon Callback

/// Carbon event handler for `kEventHotKeyPressed`. It runs on the main thread (application
/// event target); the hop to the main actor is checked rather than assumed.
nonisolated private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }

    let identifier = hotKeyID.id
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    if Thread.isMainThread {
        MainActor.assumeIsolated { manager.hotKeyPressed(id: identifier) }
    } else {
        DispatchQueue.main.async { manager.hotKeyPressed(id: identifier) }
    }
    return noErr
}

// MARK: - Hot Key IDs

private extension CaptureMode {
    /// Stable identifier passed to `RegisterEventHotKey`.
    var hotKeyID: UInt32 {
        switch self {
        case .area: 1
        case .window: 2
        case .fullScreen: 3
        }
    }

    init?(hotKeyID: UInt32) {
        guard let mode = CaptureMode.allCases.first(where: { $0.hotKeyID == hotKeyID }) else { return nil }
        self = mode
    }
}
