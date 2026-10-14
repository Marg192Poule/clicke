import AppKit
import SwiftUI
import Observation

// MARK: - Settings Model

/// Observable mirror of `AppSettings.current`, shared by every tab of the Preferences window.
///
/// - Writing `settings` persists the new value right away through `AppSettings.current`
///   (which posts `.settingsDidChange`, so the rest of the app re-applies hotkeys, Dock icon, ...).
/// - Changes made elsewhere in the app are picked up by observing `.settingsDidChange`.
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

    /// Lives as long as the model (the model is owned by the long-lived `SettingsWindowController`).
    @ObservationIgnored private var settingsObserver: NSObjectProtocol?

    init() {
        storage = AppSettings.current
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadFromDefaults()
            }
        }
    }

    /// Re-reads the persisted settings. Does nothing if they match what's displayed (e.g. our own write).
    func reloadFromDefaults() {
        let latest = AppSettings.current
        if latest != storage {
            storage = latest
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

extension View {
    /// Runs `action` when the view appears and every time the app becomes active
    /// (e.g. when the user comes back from System Settings). No polling.
    func onAppearAndAppActivation(perform action: @escaping () -> Void) -> some View {
        self
            .onAppear(perform: action)
            .task {
                for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                    action()
                }
            }
    }
}
