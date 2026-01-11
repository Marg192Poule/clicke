import SwiftUI
internal import Combine
import AppKit
import ApplicationServices
import CoreGraphics

/// Settings section for managing app permissions (accessibility and screen recording).
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
                        // First request the permission (triggers system popup)
                        requestAccessibilityPermissions()
                        // Then open settings after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            openPrivacySettings(section: "Accessibility")
                        }
                    }
                )
                
                permissionCard(
                    title: String(localized: "screen.recording"),
                    icon: "record.circle",
                    status: hasScreenRecording,
                    action: {
                        // Request screen recording permission
                        requestScreenRecordingPermissions()
                        // Then open settings after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            openPrivacySettings(section: "ScreenCapture")
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
                                    openPrivacySettings(section: "Accessibility")
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
                                    openPrivacySettings(section: "ScreenCapture")
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
            // Check permissions immediately on startup
            checkAndUpdatePermissions()
            
            // Always start monitoring to detect changes
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
                // Accessibility permissions granted - notify to re-register hotkeys
                NotificationCenter.default.post(name: NSNotification.Name("AccessibilityPermissionsGranted"), object: nil)
            }
        }
        
        if newScreenRecordingStatus != hasScreenRecording {
            hasScreenRecording = newScreenRecordingStatus
        }
        
        // Stop polling if all permissions are granted
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
    
    /// Monitors when the application becomes active (after opening system settings).
    private func startAppActiveMonitoring() {
        appActiveSubscription = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { _ in
                // Check immediately when app becomes active
                checkAndUpdatePermissions()
            }
    }
    
    /// Monitors permission change notifications from AppDelegate.
    private func startPermissionsStatusMonitoring() {
        permissionsStatusSubscription = NotificationCenter.default.publisher(for: NSNotification.Name("PermissionsStatusChanged"))
            .sink { _ in
                // Update immediately when AppDelegate detects a change
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
    
    /// Explicitly requests accessibility permissions (triggers system popup).
    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Checks screen recording permissions.
    private func checkScreenRecordingPermissions() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        // On versions prior to macOS 10.15, permissions are not required
        return true
    }
    
    /// Explicitly requests screen recording permissions (triggers system popup).
    private func requestScreenRecordingPermissions() {
        if #available(macOS 10.15, *) {
            CGRequestScreenCaptureAccess()
        }
    }
    
    /// Opens the System Settings/Preferences for the specified privacy section.
    /// - Parameter section: The privacy section to open ("Accessibility" or "ScreenCapture").
    private func openPrivacySettings(section: String) {
        // Handle different macOS versions
        if #available(macOS 13.0, *) {
            // macOS Ventura (13.0+) and later - uses System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        
        // macOS Monterey (12.0) and earlier - uses System Preferences
        // Try the modern URL first
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)") {
            NSWorkspace.shared.open(url)
            return
        }
        
        // Fallback: open security preference pane directly
        let prefPanePath = "/System/Library/PreferencePanes/Security.prefPane"
        if FileManager.default.fileExists(atPath: prefPanePath) {
            let prefPaneURL = URL(fileURLWithPath: prefPanePath)
            if #available(macOS 10.15, *) {
                NSWorkspace.shared.open([prefPaneURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/System Preferences.app"), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            } else {
                NSWorkspace.shared.open(prefPaneURL)
            }
        } else {
            // Last resort: open System Preferences
            if #available(macOS 10.15, *) {
                if let systemPrefsURL = URL(string: "file:///System/Applications/System%20Preferences.app") {
                    NSWorkspace.shared.openApplication(at: systemPrefsURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                }
            } else {
                // For very old versions, use the old method
                if let url = URL(string: "x-apple.systempreferences:") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
