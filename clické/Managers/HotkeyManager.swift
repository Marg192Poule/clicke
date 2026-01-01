import AppKit

class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var currentConfiguration: HotkeyConfiguration
    private var onHotkeyPressed: (() -> Void)?

    init() {
        self.currentConfiguration = Settings.current.hotkey
    }

    // callback when hotkey pressed
    func setHotkeyHandler(_ handler: @escaping () -> Void) {
        self.onHotkeyPressed = handler
    }

    // save global hotkey with the actual config
    func registerHotkey() {
        unregisterHotkey()
        currentConfiguration = Settings.current.hotkey

        // event capture even if the app is not active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.currentConfiguration.matches(event: event) == true {
                self?onHotkeyPressed?()
            }
        }
        
        // event capture when app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.currentConfiguration.matches(event: event) == true {
                self?.onHotkeyPressed?()
                return nil // consume the event
            }
            return event
        }
    }

    func unregisterHotkey() {
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    // maj && register new hotkey
    func updateConfiguration(_ config: HotkeyConfiguration) {
        var settings = Settings.current
        settings.hotkey = config 
        Settings.current = settings
        registerHotkey()
    }

    // verif access permission 
    static func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}