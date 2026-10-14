import AppKit
import SwiftUI
import Observation
import ServiceManagement

// MARK: - Settings Model

/// Observable mirror of `AppSettings.current` (plus a few system statuses), shared by every tab of
/// the Preferences window.
///
/// - Writing `settings` persists the new value right away through `AppSettings.current`
///   (which posts `.settingsDidChange`, so the rest of the app re-applies hotkeys, Dock icon, ...).
/// - While the window is open (between `startUpdating()` and `stopUpdating()`), changes made elsewhere
///   in the app are picked up by observing `.settingsDidChange` and `.hotkeyAvailabilityDidChange`.
///   While it's closed, nothing is observed or refreshed: `startUpdating()` catches up before it reappears.
/// - System statuses (login item, Screen Recording) are only re-read when the window appears or
///   becomes key (e.g. when the user comes back from System Settings). Nothing is polled.
///
/// Both directions compare values before doing anything, so a write can never bounce back into another write.
@Observable
final class SettingsModel {
    /// The settings displayed by the window. Assigning a different value saves it.
    var settings: AppSettings {
        get { storage }
        set {
            guard newValue != storage else { return }
            storage = newValue
            AppSettings.current = newValue
        }
    }

    private var storage: AppSettings

    /// Shortcuts enabled in `settings` that aren't active (see `HotkeyAvailability`).
    private(set) var unavailableHotkeys: Set<HotkeyConfiguration>

    /// Whether Clické opens at login (`SMAppService.mainApp`).
    private(set) var loginItemStatus: SMAppService.Status

    /// Whether Clické has the Screen Recording permission.
    private(set) var hasScreenRecordingAccess: Bool

    /// Notification observers, registered only while the window is open.
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        storage = AppSettings.current
        unavailableHotkeys = HotkeyAvailability.unavailable
        loginItemStatus = SMAppService.mainApp.status
        hasScreenRecordingAccess = ScreenRecordingPermission.isGranted
    }

    // MARK: Window Lifecycle

    /// Call before the window appears: catches up with what changed while it was closed, then
    /// follows changes until `stopUpdating()`.
    func startUpdating() {
        reloadFromDefaults()
        reloadHotkeyAvailability()
        refreshSystemStatus()

        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .settingsDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reloadFromDefaults()
                }
            },
            center.addObserver(forName: .hotkeyAvailabilityDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reloadHotkeyAvailability()
                }
            },
        ]
    }

    /// Call when the window closes: stops following changes.
    func stopUpdating() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }

    // MARK: Refreshing

    /// Re-reads the persisted settings. Does nothing if they match what's displayed (e.g. our own write).
    private func reloadFromDefaults() {
        let latest = AppSettings.current
        if latest != storage {
            storage = latest
        }
    }

    private func reloadHotkeyAvailability() {
        let latest = HotkeyAvailability.unavailable
        if latest != unavailableHotkeys {
            unavailableHotkeys = latest
        }
    }

    /// Re-reads the statuses the user can change in System Settings. Called when the window appears or
    /// becomes key, and after changing the login item.
    func refreshSystemStatus() {
        let status = SMAppService.mainApp.status
        if status != loginItemStatus {
            loginItemStatus = status
        }
        let access = ScreenRecordingPermission.isGranted
        if access != hasScreenRecordingAccess {
            hasScreenRecordingAccess = access
        }
    }
}

// MARK: - Layout

/// Shared metrics for the Preferences tabs.
enum SettingsLayout {
    /// Every tab has the same width; only the window height changes between tabs.
    static let contentWidth: CGFloat = 520
}

/// Root view of a Preferences tab: fixed width, natural height, pinned to the top.
///
/// It reports the content's natural size through `onSizeChange` whenever it changes (e.g. when a
/// footer or an inline message appears), so the window can fit the tab. Pinning to the top keeps the
/// content still while the window frame animates.
struct SettingsTabContainer<Content: View>: View {
    let onSizeChange: (CGSize) -> Void
    let content: Content

    var body: some View {
        content
            .frame(width: SettingsLayout.contentWidth)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                onSizeChange(size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
