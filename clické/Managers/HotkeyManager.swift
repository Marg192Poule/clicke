import AppKit
import ApplicationServices

/// Manager for registering and detecting global keyboard shortcuts.
/// Supports multiple hotkeys (screenshot and tab capture).
class HotkeyManager {
    
    // MARK: - Hotkey Handler
    
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
    
    /// Configures the callback for the screenshot hotkey.
    /// - Parameter handler: The closure to execute when the hotkey is pressed.
    func setScreenshotHotkeyHandler(_ handler: @escaping () -> Void) {
        screenshotHandler = HotkeyHandler(
            globalMonitor: nil,
            localMonitor: nil,
            configuration: AppSettings.current.areaHotkey ?? AppSettings.defaultAreaHotkey,
            onPressed: handler
        )
    }
    
    // MARK: - Tab Capture Hotkey
    
    /// Configures the callback for the tab capture hotkey.
    /// - Parameter handler: The closure to execute when the hotkey is pressed.
    func setTabCaptureHotkeyHandler(_ handler: @escaping () -> Void) {
        tabCaptureHandler = HotkeyHandler(
            globalMonitor: nil,
            localMonitor: nil,
            configuration: AppSettings.current.windowHotkey ?? AppSettings.defaultWindowHotkey,
            onPressed: handler
        )
    }
    
    // MARK: - Register All Hotkeys
    
    /// Registers all configured hotkeys with the system.
    func registerAllHotkeys() {
        unregisterAllHotkeys()
        
        // Register screenshot hotkey
        if var handler = screenshotHandler {
            handler.configuration = AppSettings.current.areaHotkey ?? AppSettings.defaultAreaHotkey
            
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
            handler.configuration = AppSettings.current.windowHotkey ?? AppSettings.defaultWindowHotkey
            
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
    
    /// Unregisters all hotkeys from the system.
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
    
    // MARK: - Permissions
    
    /// Checks accessibility permissions without triggering a popup.
    /// - Returns: `true` if accessibility permissions are granted.
    static func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

// Temporary: NSEvent-based matching (to be replaced by Carbon hotkeys).
fileprivate extension HotkeyConfiguration {
    func matches(event: NSEvent) -> Bool {
        let eventModifiers = event.modifierFlags.intersection(Self.supportedModifiers)
        return event.keyCode == keyCode && eventModifiers == modifiers
    }
}
