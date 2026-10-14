import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - Shortcut Recorder (SwiftUI)

/// SwiftUI wrapper around `ShortcutRecorderControl`.
///
/// The recorder only checks that a combination is usable as a global shortcut
/// (`isValidGlobalShortcut`); conflicts and reserved shortcuts are handled by the caller in `onRecord`.
struct ShortcutRecorder: NSViewRepresentable {
    /// The shortcut to display (`nil` = no shortcut).
    var shortcut: HotkeyConfiguration?
    /// Accessibility title of the field, e.g. "Capture Area".
    var title: String
    /// Called when the user starts recording.
    var onRecordingStarted: () -> Void = {}
    /// Called with a combination that passed `isValidGlobalShortcut`.
    var onRecord: (HotkeyConfiguration) -> Void
    /// Called when the user cleared the shortcut (clear button, ⌫ or ⌦ while recording).
    var onClear: () -> Void
    /// Called (after a beep) when the user typed a combination that can't be a global shortcut.
    var onReject: (HotkeyConfiguration) -> Void = { _ in }

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.shortcut = shortcut
        control.title = title
        control.isEnabled = context.environment.isEnabled
        control.onRecordingStarted = onRecordingStarted
        control.onRecord = onRecord
        control.onClear = onClear
        control.onReject = onReject
    }

    static func dismantleNSView(_ control: ShortcutRecorderControl, coordinator: ()) {
        control.stopRecording()
    }
}

// MARK: - Shortcut Recorder Control (AppKit)

/// A compact, native-looking field that records a global keyboard shortcut, like the recorders in
/// System Settings › Keyboard › Keyboard Shortcuts.
///
/// - Click it (or press Space when it has keyboard focus) to start recording.
/// - While recording: type a combination to record it, Esc cancels, ⌫ / ⌦ clears the shortcut.
///   Clicking elsewhere, switching tabs, closing the window or switching apps cancels.
/// - `.hotkeyRecordingDidBegin` / `.hotkeyRecordingDidEnd` are always posted in pairs, so the app can
///   suspend its global hotkeys while the user types the new combination.
final class ShortcutRecorderControl: NSView {

    // MARK: Public State

    /// The shortcut displayed when not recording (`nil` = no shortcut).
    var shortcut: HotkeyConfiguration? {
        didSet {
            guard shortcut != oldValue else { return }
            updateDisplay()
        }
    }

    /// Accessibility title, e.g. "Capture Area".
    var title = "" {
        didSet { setAccessibilityLabel(String(localized: "\(title) shortcut")) }
    }

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { stopRecording() }
            field.isEnabled = isEnabled
            updateDisplay()
        }
    }

    var onRecordingStarted: (() -> Void)?
    var onRecord: ((HotkeyConfiguration) -> Void)?
    var onClear: (() -> Void)?
    var onReject: ((HotkeyConfiguration) -> Void)?

    private(set) var isRecording = false

    // MARK: Private State

    /// The recorder currently listening, if any. Only one recorder listens at a time.
    private static weak var activeRecorder: ShortcutRecorderControl?

    private static let fieldWidth: CGFloat = 132

    private let field = NSTextField(string: "")
    private let clearButton = NSButton()

    /// Modifiers held down while recording, displayed live (e.g. "⌥⇧").
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var eventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    // MARK: Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        // Defensive: recording always stops before the view leaves its window, but never leak the monitor.
        stopRecording()
    }

    private func setUp() {
        // The text field only provides the native rounded field look; this view handles all interaction.
        field.isEditable = false
        field.isSelectable = false
        field.refusesFirstResponder = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = false
        field.setAccessibilityElement(false)
        addSubview(field)

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearButtonClicked)
        clearButton.refusesFirstResponder = true
        clearButton.toolTip = String(localized: "Clear Shortcut")
        clearButton.setAccessibilityLabel(String(localized: "Clear Shortcut"))
        addSubview(clearButton)

        focusRingType = .default
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp(String(localized: "Click to record a new shortcut."))

        updateDisplay()
    }

    // MARK: Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.fieldWidth, height: field.intrinsicContentSize.height)
    }

    override func layout() {
        super.layout()
        field.frame = bounds
        let buttonSize: CGFloat = 16
        clearButton.frame = NSRect(
            x: bounds.maxX - buttonSize - 5,
            y: bounds.midY - buttonSize / 2,
            width: buttonSize,
            height: buttonSize
        )
        noteFocusRingMaskChanged()
    }

    override var focusRingMaskBounds: NSRect {
        field.cell?.focusRingMaskBounds(forFrame: field.frame, in: self) ?? bounds
    }

    override func drawFocusRingMask() {
        if let cell = field.cell {
            cell.drawFocusRingMask(withFrame: field.frame, in: self)
        } else {
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
    }

    // MARK: Display

    private func updateDisplay() {
        if isRecording {
            field.stringValue = Self.symbols(for: heldModifiers)
            field.placeholderString = String(localized: "Type shortcut…")
        } else {
            field.stringValue = shortcut?.displayString ?? ""
            field.placeholderString = String(localized: "Record shortcut")
        }
        clearButton.isHidden = isRecording || shortcut == nil || !isEnabled

        setAccessibilityValue(
            isRecording
                ? String(localized: "Recording")
                : shortcut?.displayString ?? String(localized: "None")
        )
    }

    /// Modifier symbols in the standard macOS order (⌃ ⌥ ⇧ ⌘).
    private static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }

    // MARK: Mouse & Keyboard

    /// Every click lands on this view (so the field never handles it), except clicks on the clear button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if !clearButton.isHidden, hit === clearButton || hit.isDescendant(of: clearButton) {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    /// Only reachable with Tab when Full Keyboard Access is on, like other non-text controls.
    /// This also keeps the window from focusing the recorder when it opens.
    override var canBecomeKeyView: Bool {
        isEnabled && NSApp.isFullKeyboardAccessEnabled
    }

    override func keyDown(with event: NSEvent) {
        // Reached only when focused but not recording (the event monitor handles keys while recording).
        let modifiers = event.modifierFlags.intersection(HotkeyConfiguration.supportedModifiers)
        if modifiers.isEmpty, [kVK_Space, kVK_Return].contains(Int(event.keyCode)) {
            startRecording()
        } else if modifiers.isEmpty, [kVK_Delete, kVK_ForwardDelete].contains(Int(event.keyCode)), shortcut != nil {
            onClear?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        // AppKit is already moving the focus: don't touch the first responder from here.
        stopRecording(resigningFocus: false)
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Tab switch, window closing, view removed by SwiftUI...
        if newWindow !== window {
            stopRecording()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func accessibilityPerformPress() -> Bool {
        startRecording()
        return isRecording
    }

    @objc private func clearButtonClicked() {
        stopRecording()
        onClear?()
    }

    // MARK: Recording

    func startRecording() {
        guard !isRecording, isEnabled, let window else { return }

        // End the other recorder first, so begin/end notifications never overlap.
        Self.activeRecorder?.stopRecording()
        guard window.makeFirstResponder(self) else { return }

        isRecording = true
        Self.activeRecorder = self
        heldModifiers = []

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handleWhileRecording(event)
        }

        // Switching to another app, another window, or closing the window cancels recording.
        windowObservers = [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stopRecording()
                }
            }
        }

        updateDisplay()
        NotificationCenter.default.post(name: .hotkeyRecordingDidBegin, object: nil)
        onRecordingStarted?()
    }

    /// Stops listening (if recording). Always removes the event monitor and posts `.hotkeyRecordingDidEnd`.
    /// - Parameter resigningFocus: Whether to also give up the keyboard focus.
    func stopRecording(resigningFocus: Bool = true) {
        guard isRecording else { return }
        isRecording = false

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers = []
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
        heldModifiers = []

        if resigningFocus, let window, window.firstResponder === self {
            window.makeFirstResponder(nil)
        }
        updateDisplay()
        NotificationCenter.default.post(name: .hotkeyRecordingDidEnd, object: nil)
    }

    private func handleWhileRecording(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            return handleKeyDown(event)

        case .flagsChanged:
            heldModifiers = event.modifierFlags.intersection(HotkeyConfiguration.supportedModifiers)
            updateDisplay()
            return event

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // A click anywhere else cancels; the click itself still goes through.
            let location = convert(event.locationInWindow, from: nil)
            if event.window !== window || !bounds.insetBy(dx: -2, dy: -2).contains(location) {
                stopRecording()
            }
            return event

        default:
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(HotkeyConfiguration.supportedModifiers)

        if modifiers.isEmpty {
            switch Int(event.keyCode) {
            case kVK_Escape:
                stopRecording()
                return nil
            case kVK_Delete, kVK_ForwardDelete:
                stopRecording()
                onClear?()
                return nil
            case kVK_Tab:
                // Let AppKit move the focus to the next control.
                stopRecording()
                return event
            default:
                break
            }
        }

        guard !event.isARepeat else { return nil }

        let recorded = HotkeyConfiguration(keyCode: event.keyCode, modifiers: modifiers)
        guard recorded.isValidGlobalShortcut else {
            NSSound.beep()
            onReject?(recorded)
            return nil
        }

        stopRecording()
        onRecord?(recorded)
        return nil
    }
}
