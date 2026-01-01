import AppKit
import ApplicationServices

/// Gestionnaire pour enregistrer et détecter les raccourcis clavier globaux
/// Supporte plusieurs hotkeys (screenshot et tabCapture)
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
        // Les handlers seront configurés via les méthodes setHotkeyHandler
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
    /// Enregistre tous les hotkeys configurés
    func registerAllHotkeys() {
        unregisterAllHotkeys()
        
        // Enregistrer screenshot hotkey
        if var handler = screenshotHandler {
            handler.configuration = Settings.current.hotkey
            
            // Monitor global pour capturer les événements même quand l'app n'est pas active
            handler.globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if handler.configuration.matches(event: event) {
                    handler.onPressed?()
                }
            }
            
            // Monitor local pour capturer les événements quand l'app est active
            handler.localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if handler.configuration.matches(event: event) {
                    handler.onPressed?()
                    return nil  // Consommer l'événement pour éviter le comportement système
                }
                return event
            }
            
            screenshotHandler = handler
        }
        
        // Enregistrer tab capture hotkey
        if var handler = tabCaptureHandler {
            handler.configuration = Settings.current.tabCaptureHotkey
            
            // Monitor global pour capturer les événements même quand l'app n'est pas active
            handler.globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if handler.configuration.matches(event: event) {
                    handler.onPressed?()
                }
            }
            
            // Monitor local pour capturer les événements quand l'app est active
            handler.localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if handler.configuration.matches(event: event) {
                    handler.onPressed?()
                    return nil  // Consommer l'événement pour éviter le comportement système
                }
                return event
            }
            
            tabCaptureHandler = handler
        }
    }
    
    // MARK: - Unregister All Hotkeys
    /// Désenregistre tous les hotkeys
    func unregisterAllHotkeys() {
        // Désenregistrer screenshot hotkey
        if let globalMonitor = screenshotHandler?.globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor = screenshotHandler?.localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        screenshotHandler?.globalMonitor = nil
        screenshotHandler?.localMonitor = nil
        
        // Désenregistrer tab capture hotkey
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
    /// Met à jour la configuration du screenshot hotkey et réenregistre
    func updateScreenshotHotkeyConfiguration(_ config: HotkeyConfiguration) {
        var settings = Settings.current
        settings.hotkey = config
        Settings.current = settings
        registerAllHotkeys()
    }
    
    /// Met à jour la configuration du tab capture hotkey et réenregistre
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
    /// Vérifie les permissions d'accessibilité
    static func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // Legacy alias
    static func checkAccessibilityPermission() -> Bool {
        return checkAccessibilityPermissions()
    }
}
