import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private let toastManager = ToastManager()
    private var settingsWindow: NSWindow?
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
        
        NSApp.setActivationPolicy(.accessory)
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
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder", 
                accessibilityDescription: "Screenshot"
            )
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Screenshot",
                action: #selector(screenshotCapture),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Capture Window",
                action: #selector(tabCapture),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Preferences",
                action: #selector(openSettings),
                keyEquivalent: ","
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Quit",
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
                // Récupérer l'image du presse-papier
                if let image = NSPasteboard.general.readObjects(
                    forClasses: [NSImage.self],
                    options: nil
                )?.first as? NSImage {
                    // Afficher le toast interactif avec option Edit
                    toastManager.showWithEditOption(
                        message: "Copied",
                        icon: "doc.on.clipboard.fill",
                        screenshotImage: image
                    )
                } else {
                    // Fallback au toast simple
                    toastManager.show(
                        message: "Copied",
                        icon: "doc.on.clipboard.fill",
                        success: true
                    )
                }
            }
        } catch {
            toastManager.show(
                message: "Error",
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
                // Récupérer l'image du presse-papier
                if let image = NSPasteboard.general.readObjects(
                    forClasses: [NSImage.self],
                    options: nil
                )?.first as? NSImage {
                    // Afficher le toast interactif avec option Edit
                    toastManager.showWithEditOption(
                        message: "Window captured",
                        icon: "macwindow",
                        screenshotImage: image
                    )
                } else {
                    // Fallback au toast simple
                    toastManager.show(
                        message: "Window captured",
                        icon: "macwindow",
                        success: true
                    )
                }
            }
        } catch {
            toastManager.show(
                message: "Error",
                icon: "xmark.circle.fill",
                success: false
            )
        }
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
}

