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
/// Shortcuts are re-registered when settings change and suspended while the Settings window
/// records a new shortcut. Enabled shortcuts that aren't active (taken by another app, or not a
/// valid global shortcut) are published in `HotkeyAvailability.unavailable`. Failed registrations
/// are retried whenever Clické becomes active: the other app may have quit in the meantime.
final class HotkeyManager: NSObject {

    // MARK: - Properties

    private let onHotkey: (CaptureMode) -> Void
    private var eventHandler: EventHandlerRef?

    /// A hot key registered successfully.
    private struct Registration {
        let configuration: HotkeyConfiguration
        let ref: EventHotKeyRef
    }

    /// The active hot keys only (failed registrations are never stored here).
    private var registrations: [CaptureMode: Registration] = [:]
    /// The enabled shortcuts from the settings, as last applied.
    private var desiredConfigurations: [CaptureMode: HotkeyConfiguration] = [:]
    /// Number of shortcut recorders listening: hot keys stay unregistered while it's above zero.
    private var suspendCount = 0
    private var isStarted = false

    /// Shortcuts the user was already warned about this session.
    private var reportedFailures: Set<HotkeyConfiguration> = []

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
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        desiredConfigurations = currentConfigurations()
        applyRegistrations()
    }

    /// Unregisters everything.
    func stop() {
        guard isStarted else { return }
        isStarted = false

        NotificationCenter.default.removeObserver(self)
        unregisterAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    // MARK: - Notifications

    @objc private func settingsDidChange() {
        let configurations = currentConfigurations()
        guard configurations != desiredConfigurations else { return }
        desiredConfigurations = configurations
        applyRegistrations()
    }

    @objc private func recordingDidBegin() {
        suspendCount += 1
        if suspendCount == 1 {
            unregisterAll()
        }
    }

    @objc private func recordingDidEnd() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        guard suspendCount == 0 else { return }
        desiredConfigurations = currentConfigurations()
        applyRegistrations()
    }

    /// A shortcut taken by another app may have been released since: try the failed ones again.
    @objc private func applicationDidBecomeActive() {
        guard !HotkeyAvailability.unavailable.isEmpty else { return }
        applyRegistrations()
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

    /// Makes the registered hot keys match `desiredConfigurations`: unregisters the ones that were
    /// changed or disabled, registers the missing ones (retrying earlier failures), then publishes
    /// the enabled shortcuts that still aren't active.
    private func applyRegistrations() {
        guard isStarted, suspendCount == 0 else { return }

        // Release changed shortcuts first, so two modes can swap their shortcuts.
        for (mode, registration) in registrations where desiredConfigurations[mode] != registration.configuration {
            UnregisterEventHotKey(registration.ref)
            registrations[mode] = nil
        }

        var unavailable: Set<HotkeyConfiguration> = []
        var failures: [RegistrationFailure] = []

        for mode in CaptureMode.allCases {
            guard let configuration = desiredConfigurations[mode], registrations[mode] == nil else { continue }

            // A shortcut without ⌘ ⌥ ⌃ (other than an F-key) would swallow normal typing.
            guard configuration.isValidGlobalShortcut else {
                logger.warning("Not registering \(configuration.displayString, privacy: .public): not a valid global shortcut")
                unavailable.insert(configuration)
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
                registrations[mode] = Registration(configuration: configuration, ref: hotKeyRef)
                logger.debug("Registered \(configuration.displayString, privacy: .public)")
            } else {
                // eventHotKeyExistsErr (-9878): another app already uses the combination.
                logger.error("Couldn't register \(configuration.displayString, privacy: .public) (OSStatus \(status, privacy: .public))")
                unavailable.insert(configuration)
                failures.append(RegistrationFailure(configuration: configuration, status: status))
            }
        }

        HotkeyAvailability.unavailable = unavailable
        reportFailures(failures)
    }

    private struct RegistrationFailure {
        let configuration: HotkeyConfiguration
        let status: OSStatus
    }

    /// Tells the user, once per shortcut and per session, that a shortcut doesn't work.
    private func reportFailures(_ failures: [RegistrationFailure]) {
        let newFailures = failures.filter { !reportedFailures.contains($0.configuration) }
        guard let first = newFailures.first else { return }
        reportedFailures.formUnion(newFailures.map(\.configuration))

        let message: String
        if newFailures.count > 1 {
            let list = ListFormatter.localizedString(byJoining: newFailures.map(\.configuration.displayString))
            message = String(
                localized: "Shortcuts \(list) Aren’t Available",
                comment: "Toast: several capture shortcuts couldn’t be registered (list of shortcuts)"
            )
        } else if first.status == OSStatus(eventHotKeyExistsErr) {
            message = String(
                localized: "Shortcut \(first.configuration.displayString) Is Used by Another App",
                comment: "Toast: a capture shortcut is already taken by another app"
            )
        } else {
            message = String(
                localized: "Shortcut \(first.configuration.displayString) Isn’t Available",
                comment: "Toast: macOS refused to register a capture shortcut"
            )
        }
        ToastManager.shared.show(message: message, icon: "exclamationmark.triangle.fill", success: false)
    }

    /// Unregisters every hot key. The shortcuts stay desired: `applyRegistrations()` brings them back.
    private func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
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
