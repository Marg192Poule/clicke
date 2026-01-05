import SwiftUI
import AppKit
import ApplicationServices

/// Vue principale avec sidebar (utilisée dans AppSettingsView)
struct SettingsContentView: View {
    @State private var settings: Settings = Settings.current
    @State private var isSettingHotKey = false
    @State private var currentModifiers: NSEvent.ModifierFlags = []
    @State private var showAccessibilityAlert = false
    
    var body: some View {
        Form {
            // Permissions Section (si nécessaire)
            if !checkAccessibilityPermissions() {
                PermissionsSectionView(showAlert: $showAccessibilityAlert)
            }
            
            // Hotkey Section
            HotKeySectionView(
                configuration: $settings.hotkey,
                isSettingHotKey: $isSettingHotKey,
                currentModifiers: $currentModifiers
            )
            
            // Tab Capture Hotkey Section
            TabCaptureHotKeySectionView(
                configuration: $settings.tabCaptureHotkey,
                isSettingHotKey: $isSettingHotKey,
                currentModifiers: $currentModifiers
            )
            
            // Apparence Section
            AppearanceSectionView(
                showDockIcon: $settings.showDockIcon
            )
            
            // General Section
            GeneralSectionView(
                copyToClipboard: $settings.copyToClipboard
            )
            
            // Sound Section
            SoundSectionView(
                soundEnabled: $settings.soundEffectsEnabled,
                volume: $settings.soundEffectsVolume,
                selectedSound: $settings.captureSound
            )
        }
        .formStyle(.grouped)
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.4), location: 0.03),
                    .init(color: .black.opacity(0.7), location: 0.06),
                    .init(color: .black.opacity(0.9), location: 0.09),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onChange(of: settings) { oldValue, newValue in
            Settings.current = newValue
            // Notifier AppDelegate pour mettre à jour le hotkey
            NotificationCenter.default.post(name: NSNotification.Name("HotkeyConfigurationChanged"), object: nil)
            // Mettre à jour le dock icon
            NotificationCenter.default.post(name: NSNotification.Name("DockIconChanged"), object: nil)
        }
        .alert("Permissions Required", isPresented: $showAccessibilityAlert) {
            Button("OK") { }
        } message: {
            Text("Clické needs accessibility permissions to function. Please allow the app in System Settings > Privacy & Security > Accessibility.")
        }
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

/// Vue wrapper pour compatibilité (utilisée directement sans sidebar)
struct SettingsView: View {
    var body: some View {
        AppSettingsView()
    }
}



/// Contenu de la section À propos
struct AboutContentView: View {
    var body: some View {
        Form {
            AboutSectionView()
        }
        .formStyle(.grouped)
    }
}

