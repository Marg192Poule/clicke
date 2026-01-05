import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private let toastManager = ToastManager()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
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
        
        // Appliquer le paramètre initial
        updateDockIconVisibility()
        
        // Show onboarding if first launch
        if !OnboardingViewModel.hasCompletedOnboarding() {
            showOnboarding()
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

    private func showOnboarding() {
        let onboardingView = OnboardingView()
        onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        onboardingWindow?.isReleasedWhenClosed = false
        onboardingWindow?.delegate = self
        onboardingWindow?.title = "Welcome to Clické"
        onboardingWindow?.contentView = NSHostingView(rootView: onboardingView)
        onboardingWindow?.center()
        onboardingWindow?.titlebarAppearsTransparent = true
        onboardingWindow?.titleVisibility = .hidden
        onboardingWindow?.backgroundColor = .clear
        onboardingWindow?.isOpaque = false
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        } else if window === onboardingWindow {
            onboardingWindow = nil
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
}

