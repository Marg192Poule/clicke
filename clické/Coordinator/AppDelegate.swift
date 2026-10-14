import AppKit
import SwiftUI
import ApplicationServices
import CoreGraphics

// MARK: - Capture Mode

/// Defines the type of screen capture to perform.
enum CaptureMode {
    case area      // Interactive area selection (-i flag)
    case window    // Window capture (-w flag)
    
    var screencaptureFlag: String {
        switch self {
        case .area: return "-i"
        case .window: return "-w"
        }
    }
    
    var successMessage: String {
        switch self {
        case .area: return String(localized: "copied")
        case .window: return String(localized: "window captured")
        }
    }
    
    var icon: String {
        switch self {
        case .area: return "doc.on.clipboard.fill"
        case .window: return "macwindow"
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let toastManager = ToastManager()
    private let hotkeyManager = HotkeyManager()
    private var permissionsCheckTimer: Timer?
    private var lastAccessibilityStatus = false
    private var lastScreenRecordingStatus = false
    private var lastScreenRecordingCheckTime: TimeInterval?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        
        // Check permissions (without automatically re-requesting)
        // Only request permissions when user explicitly clicks a button
        checkInitialPermissionsStatus()
        
        setupHotkeys()
        
        // Listen for dock icon changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dockIconChanged),
            name: NSNotification.Name("DockIconChanged"),
            object: nil
        )
        
        // Listen for keyboard shortcut changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyChanged),
            name: NSNotification.Name("HotkeyConfigurationChanged"),
            object: nil
        )
        
        // Listen for when accessibility permissions are granted
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityPermissionsGranted),
            name: NSNotification.Name("AccessibilityPermissionsGranted"),
            object: nil
        )
        
        // Listen for when app becomes active (to detect permission changes)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Start continuous permissions polling
        startContinuousPermissionsCheck()
        
        // Apply initial setting
        updateDockIconVisibility()
    }
    
    // MARK: - Permissions Monitoring
    
    /// Starts continuous background permissions checking
    private func startContinuousPermissionsCheck() {
        // Initialize initial states (without triggering popup)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        lastAccessibilityStatus = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if #available(macOS 10.15, *) {
            // Check screen recording permissions (may trigger popup first time)
            // But we only do this once at startup
            lastScreenRecordingStatus = CGPreflightScreenCaptureAccess()
        } else {
            lastScreenRecordingStatus = true
        }
        
        // If permissions already granted, re-register hotkeys immediately
        if lastAccessibilityStatus {
            DispatchQueue.main.async { [weak self] in
                self?.hotkeyManager.registerAllHotkeys()
            }
        }
        
        // Create timer that checks permissions every 1 second (less aggressive)
        // We only check to detect when they're granted, not to re-request them
        permissionsCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermissionsStatus()
        }
        
        // Ensure timer works even when app is in background
        RunLoop.current.add(permissionsCheckTimer!, forMode: .common)
    }
    
    /// Checks permissions status and reacts to changes (without re-requesting)
    private func checkPermissionsStatus() {
        // Check accessibility permissions (without triggering popup)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let currentAccessibilityStatus = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // For screen recording, we DON'T check every time because CGPreflightScreenCaptureAccess()
        // can trigger a popup. We only check if we think we don't have permissions,
        // and only every 10 seconds to avoid repeated popups.
        var currentScreenRecordingStatus = lastScreenRecordingStatus
        if !lastScreenRecordingStatus {
            if #available(macOS 10.15, *) {
                let now = Date().timeIntervalSince1970
                if let lastCheck = lastScreenRecordingCheckTime {
                    // Only check every 10 seconds to avoid popups
                    if now - lastCheck > 10.0 {
                        currentScreenRecordingStatus = CGPreflightScreenCaptureAccess()
                        lastScreenRecordingCheckTime = now
                    }
                } else {
                    currentScreenRecordingStatus = CGPreflightScreenCaptureAccess()
                    lastScreenRecordingCheckTime = now
                }
            } else {
                currentScreenRecordingStatus = true
            }
        }
        
        // If accessibility permissions changed
        if currentAccessibilityStatus != lastAccessibilityStatus {
            lastAccessibilityStatus = currentAccessibilityStatus
            if currentAccessibilityStatus {
                // Permissions granted - re-register hotkeys
                DispatchQueue.main.async { [weak self] in
                    self?.hotkeyManager.registerAllHotkeys()
                    NotificationCenter.default.post(name: NSNotification.Name("AccessibilityPermissionsGranted"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("PermissionsStatusChanged"), object: nil)
                }
            } else {
                // Permissions revoked
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("PermissionsStatusChanged"), object: nil)
                }
            }
        }
        
        // If screen recording permissions changed
        if currentScreenRecordingStatus != lastScreenRecordingStatus {
            lastScreenRecordingStatus = currentScreenRecordingStatus
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("PermissionsStatusChanged"), object: nil)
            }
        }
    }
    
    /// Checks initial permissions status (without re-requesting)
    private func checkInitialPermissionsStatus() {
        // Check accessibility permissions (without triggering popup)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if isTrusted {
            // If permissions already granted, re-register hotkeys immediately
            DispatchQueue.main.async { [weak self] in
                self?.hotkeyManager.registerAllHotkeys()
            }
        }
        
        // Check screen recording permissions (without triggering popup)
        // We only check once at startup to avoid repeated popups
        if #available(macOS 10.15, *) {
            _ = CGPreflightScreenCaptureAccess()
        }
    }
    
    // MARK: - Hotkey Setup
    
    private func setupHotkeys() {
        // Configure handler for screenshot
        hotkeyManager.setScreenshotHotkeyHandler { [weak self] in
            self?.performCapture(mode: .area)
        }
        
        // Configure handler for tab capture
        hotkeyManager.setTabCaptureHotkeyHandler { [weak self] in
            self?.performCapture(mode: .window)
        }
        
        // Register all hotkeys
        hotkeyManager.registerAllHotkeys()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
            let image = NSImage(
                systemSymbolName: "c.square.fill", 
                accessibilityDescription: "Clické"
            )?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: String(localized: "screenshot"),
                action: #selector(screenshotCapture),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: String(localized: "window capture"),
                action: #selector(tabCapture),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: String(localized: "preferences"),
                action: #selector(openSettings),
                keyEquivalent: ","
            )
        )
        menu.addItem(
            NSMenuItem(
                title: String(localized: "quit"),
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
        )

        statusItem?.menu = menu
    }

    // MARK: - Capture Actions
    
    @objc private func screenshotCapture() {
        performCapture(mode: .area)
    }
    
    @objc private func tabCapture() {
        performCapture(mode: .window)
    }
    
    /// Performs a screen capture with the specified mode.
    /// - Parameter mode: The capture mode (area selection or window)
    private func performCapture(mode: CaptureMode) {
        let pasteboardCountBefore = NSPasteboard.general.changeCount
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = [mode.screencaptureFlag, "-c", "-x"] // -c = clipboard, -x = no sound
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Check if a capture was made
            if NSPasteboard.general.changeCount != pasteboardCountBefore {
                // Play capture sound
                playCaptureSound()
                
                // Get image from clipboard
                if let image = NSPasteboard.general.readObjects(
                    forClasses: [NSImage.self],
                    options: nil
                )?.first as? NSImage {
                    // Show interactive toast with Edit option
                    toastManager.showWithEditOption(
                        message: mode.successMessage,
                        icon: mode.icon,
                        screenshotImage: image
                    )
                } else {
                    // Fallback to simple toast
                    toastManager.show(
                        message: mode.successMessage,
                        icon: mode.icon,
                        success: true
                    )
                }
            }
        } catch {
            toastManager.show(
                message: String(localized: "error"),
                icon: "xmark.circle.fill",
                success: false
            )
        }
    }
    
    private func playCaptureSound() {
        let settings = AppSettings.current
        guard settings.soundEffectsEnabled else { return }
        
        SoundManager.shared.playSound(
            settings.captureSound,
            volume: Float(settings.soundEffectsVolume)
        )
    }
    
    // MARK: - Settings Window
    
    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }
    
    // MARK: - Notification Handlers
    
    @objc private func dockIconChanged() {
        updateDockIconVisibility()
    }
    
    private func updateDockIconVisibility() {
        let settings = AppSettings.current
        if settings.showDockIcon {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    @objc private func hotkeyChanged() {
        // Re-register all hotkeys with new configurations
        hotkeyManager.registerAllHotkeys()
    }
    
    @objc private func accessibilityPermissionsGranted() {
        // Permissions have been granted - re-register hotkeys
        hotkeyManager.registerAllHotkeys()
    }
    
    @objc private func applicationDidBecomeActive() {
        // Immediately check permissions when app becomes active
        // (useful after opening system settings)
        checkPermissionsStatus()
    }
    
    deinit {
        permissionsCheckTimer?.invalidate()
    }
}
