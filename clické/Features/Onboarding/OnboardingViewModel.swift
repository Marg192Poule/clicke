import SwiftUI
import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
internal import Combine

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

class OnboardingViewModel: ObservableObject {
    @Published var screenRecordingStatus: PermissionStatus = .notDetermined
    @Published var accessibilityStatus: PermissionStatus = .notDetermined
    @Published var launchAtLogin: Bool = false {
        didSet {
            setLaunchAtLogin(launchAtLogin)
        }
    }
    
    private var permissionCheckTimer: Timer?
    
    var canContinue: Bool {
        screenRecordingStatus == .granted && accessibilityStatus == .granted
    }
    
    init() {
        // Check initial launch at login status
        launchAtLogin = SMAppService.mainApp.status == .enabled
        
        // Start polling for permission changes
        startPermissionPolling()
    }
    
    deinit {
        permissionCheckTimer?.invalidate()
    }
    
    func checkPermissions() {
        checkScreenRecordingPermission()
        checkAccessibilityPermission()
    }
    
    private func startPermissionPolling() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermissions()
        }
    }
    
    // MARK: - Screen Recording Permission
    
    private func checkScreenRecordingPermission() {
        // Check if we can list windows - this indirectly checks screen recording permission
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        
        DispatchQueue.main.async {
            // If we can read window names, we have permission
            if let windows = windowList, !windows.isEmpty {
                // Check if we can read window owner names (requires permission)
                let hasPermission = windows.first?[kCGWindowOwnerName as String] != nil
                self.screenRecordingStatus = hasPermission ? .granted : .denied
            } else {
                self.screenRecordingStatus = .denied
            }
        }
    }
    
    func requestScreenRecording() {
        // Open System Settings to Screen Recording permissions
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        
        // Show alert explaining the process
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = "Enable Screen Recording"
            alert.informativeText = "Please enable Screen Recording permission for Clické in System Settings, then return to this window."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // MARK: - Accessibility Permission
    
    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let hasPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        DispatchQueue.main.async {
            self.accessibilityStatus = hasPermission ? .granted : .denied
        }
    }
    
    func requestAccessibility() {
        // Open System Settings to Accessibility permissions
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        
        // Show alert explaining the process
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = "Enable Accessibility"
            alert.informativeText = "Please enable Accessibility permission for Clické in System Settings, then return to this window."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // MARK: - Launch at Login
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }
    
    // MARK: - Complete Onboarding
    
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
        permissionCheckTimer?.invalidate()
    }
    
    static func hasCompletedOnboarding() -> Bool {
        return UserDefaults.standard.bool(forKey: "HasCompletedOnboarding")
    }
}
