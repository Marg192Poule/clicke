import AppKit
import SwiftUI
import ApplicationServices
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private let toastManager = ToastManager()
    private var settingsWindow: NSWindow?
    private let hotkeyManager = HotkeyManager()
    private var permissionsCheckTimer: Timer?
    private var lastAccessibilityStatus = false
    private var lastScreenRecordingStatus = false
    private var lastScreenRecordingCheckTime: TimeInterval?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        
        // Vérifier les permissions (sans les redemander automatiquement)
        // On ne demande les permissions que si l'utilisateur clique explicitement sur un bouton
        checkInitialPermissionsStatus()
        
        setupHotkeys()
        
        // Écouter les changements de dock icon
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dockIconChanged),
            name: NSNotification.Name("DockIconChanged"),
            object: nil
        )
        
        // Écouter les changements de raccourci clavier
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyChanged),
            name: NSNotification.Name("HotkeyConfigurationChanged"),
            object: nil
        )
        
        // Écouter quand les permissions d'accessibilité sont accordées
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityPermissionsGranted),
            name: NSNotification.Name("AccessibilityPermissionsGranted"),
            object: nil
        )
        
        // Écouter quand l'application redevient active (pour détecter les changements de permissions)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Démarrer le polling continu des permissions
        startContinuousPermissionsCheck()
        
        // Appliquer le paramètre initial
        updateDockIconVisibility()
    }
    
    /// Démarre une vérification continue des permissions en arrière-plan
    private func startContinuousPermissionsCheck() {
        // Initialiser les états initiaux (sans déclencher de popup)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        lastAccessibilityStatus = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if #available(macOS 10.15, *) {
            // Vérifier les permissions d'enregistrement d'écran (peut déclencher un popup la première fois)
            // Mais on ne le fait qu'une seule fois au démarrage
            lastScreenRecordingStatus = CGPreflightScreenCaptureAccess()
        } else {
            lastScreenRecordingStatus = true
        }
        
        // Si les permissions sont déjà accordées, réenregistrer les hotkeys immédiatement
        if lastAccessibilityStatus {
            DispatchQueue.main.async { [weak self] in
                self?.hotkeyManager.registerAllHotkeys()
            }
        }
        
        // Créer un timer qui vérifie les permissions toutes les 1 seconde (moins agressif)
        // On vérifie seulement pour détecter quand elles sont accordées, pas pour les redemander
        permissionsCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermissionsStatus()
        }
        
        // S'assurer que le timer fonctionne même quand l'app est en arrière-plan
        RunLoop.current.add(permissionsCheckTimer!, forMode: .common)
    }
    
    /// Vérifie le statut des permissions et réagit aux changements (sans redemander)
    private func checkPermissionsStatus() {
        // Vérifier les permissions d'accessibilité (sans déclencher de popup)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let currentAccessibilityStatus = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Pour l'enregistrement d'écran, on ne vérifie PAS à chaque fois car CGPreflightScreenCaptureAccess()
        // peut déclencher un popup. On ne vérifie que si on pense qu'on n'a pas les permissions,
        // et seulement toutes les 10 secondes pour éviter les popups répétés.
        var currentScreenRecordingStatus = lastScreenRecordingStatus
        if !lastScreenRecordingStatus {
            if #available(macOS 10.15, *) {
                let now = Date().timeIntervalSince1970
                if let lastCheck = lastScreenRecordingCheckTime {
                    // Vérifier seulement toutes les 10 secondes pour éviter les popups
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
        
        // Si les permissions d'accessibilité ont changé
        if currentAccessibilityStatus != lastAccessibilityStatus {
            lastAccessibilityStatus = currentAccessibilityStatus
            if currentAccessibilityStatus {
                // Permissions accordées - réenregistrer les hotkeys
                DispatchQueue.main.async { [weak self] in
                    self?.hotkeyManager.registerAllHotkeys()
                    NotificationCenter.default.post(name: NSNotification.Name("AccessibilityPermissionsGranted"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("PermissionsStatusChanged"), object: nil)
                }
            } else {
                // Permissions retirées
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("PermissionsStatusChanged"), object: nil)
                }
            }
        }
        
        // Si les permissions d'enregistrement d'écran ont changé
        if currentScreenRecordingStatus != lastScreenRecordingStatus {
            lastScreenRecordingStatus = currentScreenRecordingStatus
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("PermissionsStatusChanged"), object: nil)
            }
        }
    }
    
    /// Vérifie l'état initial des permissions (sans les redemander)
    private func checkInitialPermissionsStatus() {
        // Vérifier les permissions d'accessibilité (sans déclencher de popup)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if isTrusted {
            // Si les permissions sont déjà accordées, réenregistrer les hotkeys immédiatement
            DispatchQueue.main.async { [weak self] in
                self?.hotkeyManager.registerAllHotkeys()
            }
        }
        
        // Vérifier les permissions d'enregistrement d'écran (sans déclencher de popup)
        // On ne vérifie qu'une seule fois au démarrage pour éviter les popups répétés
        if #available(macOS 10.15, *) {
            _ = CGPreflightScreenCaptureAccess()
        }
    }
    
    private func setupHotkeys() {
        // Configurer le handler pour screenshot
        hotkeyManager.setScreenshotHotkeyHandler { [weak self] in
            self?.screenshotCapture()
        }
        
        // Configurer le handler pour tab capture
        hotkeyManager.setTabCaptureHotkeyHandler { [weak self] in
            self?.tabCapture()
        }
        
        // Enregistrer tous les hotkeys
        hotkeyManager.registerAllHotkeys()
    }

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

    @objc private func screenshotCapture() {
        // Vérifier les permissions avant de capturer
        // Si les permissions ne sont pas accordées, on ne peut pas capturer
        // Note: screencapture lui-même peut déclencher un popup si les permissions ne sont pas accordées
        // mais on essaie de l'éviter en vérifiant d'abord
        
        // Utiliser l'interface native de macOS
        let pasteboardCountBefore = NSPasteboard.general.changeCount
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-c", "-x"] // -i = interactif natif, -c = clipboard, -x = pas de son
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Vérifier si une capture a été faite
            if NSPasteboard.general.changeCount != pasteboardCountBefore {
                // Jouer le son de capture
                playCaptureSound()
                
                // Récupérer l'image du presse-papier
                if let image = NSPasteboard.general.readObjects(
                    forClasses: [NSImage.self],
                    options: nil
                )?.first as? NSImage {
                    // Afficher le toast interactif avec option Edit
                    toastManager.showWithEditOption(
                        message: String(localized: "copied"),
                        icon: "doc.on.clipboard.fill",
                        screenshotImage: image
                    )
                } else {
                    // Fallback au toast simple
                    toastManager.show(
                        message: String(localized: "copied"),
                        icon: "doc.on.clipboard.fill",
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
    
    @objc private func tabCapture() {
        // Obtenir la fenêtre active et capturer seulement l'onglet/la fenêtre
        let pasteboardCountBefore = NSPasteboard.general.changeCount
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-w", "-c", "-x"] // -w = window only, -c = clipboard, -x = pas de son
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Vérifier si une capture a été faite
            if NSPasteboard.general.changeCount != pasteboardCountBefore {
                // Jouer le son de capture
                playCaptureSound()
                
                // Récupérer l'image du presse-papier
                if let image = NSPasteboard.general.readObjects(
                    forClasses: [NSImage.self],
                    options: nil
                )?.first as? NSImage {
                    // Afficher le toast interactif avec option Edit
                    toastManager.showWithEditOption(
                        message: String(localized: "window.captured"),
                        icon: "macwindow",
                        screenshotImage: image
                    )
                } else {
                    // Fallback au toast simple
                    toastManager.show(
                        message: String(localized: "window.captured"),
                        icon: "macwindow",
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
        let settings = Settings.current
        guard settings.soundEffectsEnabled else { return }
        
        SoundManager.shared.playSound(
            settings.captureSound,
            volume: Float(settings.soundEffectsVolume)
        )
    }
    
    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = AppSettingsView()
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                styleMask: [.fullSizeContentView, .titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.delegate = self
            settingsWindow?.title = "Preferences"
            settingsWindow?.contentView = NSHostingView(rootView: settingsView)
            settingsWindow?.center()
            settingsWindow?.titlebarAppearsTransparent = true
            settingsWindow?.titleVisibility = .hidden
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
        }
    }
    
    @objc private func dockIconChanged() {
        updateDockIconVisibility()
    }
    
    private func updateDockIconVisibility() {
        let settings = Settings.current
        if settings.showDockIcon {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    @objc private func quitApp(){
        NSApp.terminate(nil)
    }
    
    @objc private func hotkeyChanged() {
        // Réenregistrer tous les hotkeys avec les nouvelles configurations
        hotkeyManager.registerAllHotkeys()
    }
    
    @objc private func accessibilityPermissionsGranted() {
        // Les permissions ont été accordées - réenregistrer les hotkeys
        hotkeyManager.registerAllHotkeys()
    }
    
    @objc private func applicationDidBecomeActive() {
        // Vérifier immédiatement les permissions quand l'app redevient active
        // (utile après avoir ouvert les paramètres système)
        checkPermissionsStatus()
    }
    
    deinit {
        permissionsCheckTimer?.invalidate()
    }
}

