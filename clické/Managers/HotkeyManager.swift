import AppKit
import ApplicationServices

/// Manager for registering and detecting global keyboard shortcuts.
/// Supports multiple hotkeys (screenshot and tabCapture).
class HotkeyManager {
    // MARK: - Hotkey Handlers
    private struct HotkeyHandler {
        var globalMonitor: Any?
        var localMonitor: Any?
        var configuration: HotkeyConfiguration
        var onPressed: (() -> Void)?
    }
    
    private var screenshotHandler: HotkeyHandler?
    private var tabCaptureHandler: HotkeyHandler?
    
    // MARK: - Initialization
    init() {
        // Handlers will be configured via setHotkeyHandler methods
    }
    
    // MARK: - Screenshot Hotkey
    /// Configure le callback pour le hotkey de screenshot
    func setScreenshotHotkeyHandler(_ handler: @escaping () -> Void) {
        screenshotHandler = HotkeyHandler(
            globalMonitor: nil,
            localMonitor: nil,
            configuration: Settings.current.hotkey,
            onPressed: handler
        )
    }
    
    // MARK: - Tab Capture Hotkey
    /// Configure le callback pour le hotkey de tab capture
    func setTabCaptureHotkeyHandler(_ handler: @escaping () -> Void) {
        tabCaptureHandler = HotkeyHandler(
            globalMonitor: nil,
            localMonitor: nil,
            configuration: Settings.current.tabCaptureHotkey,
            onPressed: handler
        )
    }
    
    // MARK: - Register All Hotkeys
    /// Registers all configured hotkeys
    func registerAllHotkeys() {
        unregisterAllHotkeys()
        
        // Register screenshot hotkey
        if var handler = screenshotHandler {
            handler.configuration = Settings.current.hotkey
            
            // Global monitor to capture events even when app is not active
            handler.globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if handler.configuration.matches(event: event) {
                    handler.onPressed?()
                }
            }
            
            // Local monitor to capture events when app is active
            handler.localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if handler.configuration.matches(event: event) {
                    handler.onPressed?()
                    return nil  // Consume event to prevent system behavior
                }
                return event
            }
            
            screenshotHandler = handler
        }
        
        // Register tab capture hotkey
        if var handler = tabCaptureHandler {
            handler.configuration = Settings.current.tabCaptureHotkey
            
            // Global monitor to capture events even when app is not active
            handler.globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if handler.configuration.matches(event: event) {
                    handler.onPressed?()
                }
            }
            
            // Local monitor to capture events when app is active
            handler.localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if handler.configuration.matches(event: event) {
                    handler.onPressed?()
                    return nil  // Consume event to prevent system behavior
                }
                return event
            }
            
            tabCaptureHandler = handler
        }
    }
    
    // MARK: - Unregister All Hotkeys
    /// Unregisters all hotkeys
    func unregisterAllHotkeys() {
        // Unregister screenshot hotkey
        if let globalMonitor = screenshotHandler?.globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor = screenshotHandler?.localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        screenshotHandler?.globalMonitor = nil
        screenshotHandler?.localMonitor = nil
        
        // Unregister tab capture hotkey
        if let globalMonitor = tabCaptureHandler?.globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor = tabCaptureHandler?.localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        tabCaptureHandler?.globalMonitor = nil
        tabCaptureHandler?.localMonitor = nil
    }
    
    // MARK: - Update Configurations
    /// Updates screenshot hotkey configuration and re-registers
    func updateScreenshotHotkeyConfiguration(_ config: HotkeyConfiguration) {
        var settings = Settings.current
        settings.hotkey = config
        Settings.current = settings
        registerAllHotkeys()
    }
    
    /// Updates tab capture hotkey configuration and re-registers
    func updateTabCaptureHotkeyConfiguration(_ config: HotkeyConfiguration) {
        var settings = Settings.current
        settings.tabCaptureHotkey = config
        Settings.current = settings
        registerAllHotkeys()
    }
    
    // MARK: - Legacy Support (pour compatibilité)
    /// Configure le callback à appeler quand le raccourci est pressé (legacy - utilise screenshot)
    func setHotkeyHandler(_ handler: @escaping () -> Void) {
        setScreenshotHotkeyHandler(handler)
    }
    
    /// Enregistre le raccourci global avec la configuration actuelle (legacy - utilise screenshot)
    func registerHotkey() {
        registerAllHotkeys()
    }
    
    /// Désenregistre le raccourci (legacy)
    func unregisterHotkey() {
        unregisterAllHotkeys()
    }
    
    /// Met à jour la configuration et réenregistre le raccourci (legacy - utilise screenshot)
    func updateConfiguration(_ config: HotkeyConfiguration) {
        updateScreenshotHotkeyConfiguration(config)
    }
    
    // MARK: - Permissions
    /// Checks accessibility permissions (without triggering popup)
    static func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // Legacy alias
    static func checkAccessibilityPermission() -> Bool {
        return checkAccessibilityPermissions()
    }
}
