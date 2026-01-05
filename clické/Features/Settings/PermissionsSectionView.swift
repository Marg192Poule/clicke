import SwiftUI
internal import Combine
import AppKit
import ApplicationServices
import CoreGraphics

struct PermissionsSectionView: View {
    @Binding var showAlert: Bool
    @State private var hasAccessibility = false
    @State private var hasScreenRecording = false
    @State private var timerSubscription: AnyCancellable?
    @State private var appActiveSubscription: AnyCancellable?
    @State private var permissionsStatusSubscription: AnyCancellable?
    
    var body: some View {
        Section {
            VStack(spacing: 12) {
                permissionCard(
                    title: String(localized: "accessibility"),
                    icon: "accessibility",
                    status: hasAccessibility,
                    action: {
                        // D'abord demander la permission (déclenche le popup)
                        requestAccessibilityPermissions()
                        // Ensuite ouvrir les paramètres après un court délai
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            openAccessibilitySettings()
                        }
                    }
                )
                
                permissionCard(
                    title: String(localized: "screen.recording"),
                    icon: "record.circle",
                    status: hasScreenRecording,
                    action: {
                        // Demander la permission d'enregistrement d'écran
                        requestScreenRecordingPermissions()
                        // Ensuite ouvrir les paramètres après un court délai
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            openScreenRecordingSettings()
                        }
                    }
                )
            }
            
            if !hasAccessibility || !hasScreenRecording {
                VStack(alignment: .leading, spacing: 8) {
                    if !hasAccessibility {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("accessibility.description")
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    if !hasScreenRecording {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("screen.recording.description")
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        if !hasAccessibility {
                            Button {
                                requestAccessibilityPermissions()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    openAccessibilitySettings()
                                }
                            } label: {
                                Text("open.accessibility.settings")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        
                        if !hasScreenRecording {
                            Button {
                                requestScreenRecordingPermissions()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    openScreenRecordingSettings()
                                }
                            } label: {
                                Text("open.screen.recording.settings")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        } header: {
            Text("permissions")
        }
        .onAppear {
            // Vérifier immédiatement les permissions au démarrage
            checkAndUpdatePermissions()
            
            // Toujours démarrer le monitoring pour détecter les changements
            startPolling()
            startAppActiveMonitoring()
            startPermissionsStatusMonitoring()
        }
        .onDisappear {
            timerSubscription?.cancel()
            appActiveSubscription?.cancel()
            permissionsStatusSubscription?.cancel()
        }
    }
    
    private func checkAndUpdatePermissions() {
        let newAccessibilityStatus = checkAccessibilityPermissions()
        let newScreenRecordingStatus = checkScreenRecordingPermissions()
        
        if newAccessibilityStatus != hasAccessibility {
            hasAccessibility = newAccessibilityStatus
            if newAccessibilityStatus {
                // Permissions d'accessibilité accordées - notifier pour réenregistrer les hotkeys
                NotificationCenter.default.post(name: NSNotification.Name("AccessibilityPermissionsGranted"), object: nil)
            }
        }
        
        if newScreenRecordingStatus != hasScreenRecording {
            hasScreenRecording = newScreenRecordingStatus
        }
        
        // Arrêter le polling si toutes les permissions sont accordées
        if hasAccessibility && hasScreenRecording {
            timerSubscription?.cancel()
            appActiveSubscription?.cancel()
        }
    }
    
    private func startPolling() {
        timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                checkAndUpdatePermissions()
            }
    }
    
    /// Surveille quand l'application redevient active (après avoir ouvert les paramètres système)
    private func startAppActiveMonitoring() {
        appActiveSubscription = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { _ in
                // Vérifier immédiatement quand l'app redevient active
                checkAndUpdatePermissions()
            }
    }
    
    /// Surveille les notifications de changement de permissions depuis AppDelegate
    private func startPermissionsStatusMonitoring() {
        permissionsStatusSubscription = NotificationCenter.default.publisher(for: NSNotification.Name("PermissionsStatusChanged"))
            .sink { _ in
                // Mettre à jour immédiatement quand AppDelegate détecte un changement
                DispatchQueue.main.async {
                    checkAndUpdatePermissions()
                }
            }
    }
    
    @ViewBuilder
    private func permissionCard(
        title: String,
        icon: String,
        status: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            
            Spacer()
            
            if status {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)
            } else {
                Button {
                    action()
                } label: {
                    Text("allow")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Demande explicitement les permissions d'accessibilité (déclenche le popup système)
    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Vérifie les permissions d'enregistrement d'écran
    private func checkScreenRecordingPermissions() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        // Sur les versions antérieures à macOS 10.15, les permissions ne sont pas requises
        return true
    }
    
    /// Demande explicitement les permissions d'enregistrement d'écran (déclenche le popup système)
    private func requestScreenRecordingPermissions() {
        if #available(macOS 10.15, *) {
            CGRequestScreenCaptureAccess()
        }
    }
    
    private func openAccessibilitySettings() {
        // Gérer les différentes versions de macOS
        if #available(macOS 13.0, *) {
            // macOS Ventura (13.0+) et plus récent - utilise System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        
        // macOS Monterey (12.0) et versions antérieures - utilise System Preferences
        // Essayer d'abord l'URL moderne
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
            return
        }
        
        // Fallback : ouvrir directement le panneau de sécurité
        let prefPanePath = "/System/Library/PreferencePanes/Security.prefPane"
        if FileManager.default.fileExists(atPath: prefPanePath) {
            let prefPaneURL = URL(fileURLWithPath: prefPanePath)
            if #available(macOS 10.15, *) {
                NSWorkspace.shared.open([prefPaneURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/System Preferences.app"), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            } else {
                NSWorkspace.shared.open(prefPaneURL)
            }
        } else {
            // Dernier recours : ouvrir les Préférences Système
            if #available(macOS 10.15, *) {
                if let systemPrefsURL = URL(string: "file:///System/Applications/System%20Preferences.app") {
                    NSWorkspace.shared.openApplication(at: systemPrefsURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                }
            } else {
                // Pour les versions très anciennes, utiliser l'ancienne méthode
                if let url = URL(string: "x-apple.systempreferences:") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    private func openScreenRecordingSettings() {
        // Gérer les différentes versions de macOS
        if #available(macOS 13.0, *) {
            // macOS Ventura (13.0+) et plus récent - utilise System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        
        // macOS Monterey (12.0) et versions antérieures - utilise System Preferences
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
            return
        }
        
        // Fallback : ouvrir directement le panneau de sécurité
        let prefPanePath = "/System/Library/PreferencePanes/Security.prefPane"
        if FileManager.default.fileExists(atPath: prefPanePath) {
            let prefPaneURL = URL(fileURLWithPath: prefPanePath)
            if #available(macOS 10.15, *) {
                NSWorkspace.shared.open([prefPaneURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/System Preferences.app"), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            } else {
                NSWorkspace.shared.open(prefPaneURL)
            }
        } else {
            // Dernier recours : ouvrir les Préférences Système
            if #available(macOS 10.15, *) {
                if let systemPrefsURL = URL(string: "file:///System/Applications/System%20Preferences.app") {
                    NSWorkspace.shared.openApplication(at: systemPrefsURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                }
            } else {
                if let url = URL(string: "x-apple.systempreferences:") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

