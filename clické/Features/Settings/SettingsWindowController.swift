import AppKit
import SwiftUI

// MARK: - Settings Tabs

/// The tabs of the Preferences window, in toolbar order.
enum SettingsTab: String, CaseIterable {
    case general
    case capture
    case shortcuts
    case about

    /// Tab title, also used as the window title while the tab is selected.
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .capture: String(localized: "Capture")
        case .shortcuts: String(localized: "Shortcuts")
        case .about: String(localized: "About")
        }
    }

    /// SF Symbol shown in the toolbar.
    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }
}

// MARK: - Settings Window Controller

/// Owns the Preferences window. The rest of the app only calls `SettingsWindowController.shared.show()`.
///
/// The window is created once and reused: closing it only orders it out.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private static let frameAutosaveName = "ClickeSettingsWindow"

    private let model = SettingsModel()
    private let tabViewController: SettingsTabViewController
    private var hasBeenPositioned = false

    private init() {
        tabViewController = SettingsTabViewController(model: model)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentViewController = tabViewController

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the Preferences window (creating its content on first use) and brings the app to the front.
    func show() {
        guard let window else { return }

        if !window.isVisible {
            tabViewController.fitWindowToSelectedTab(animated: false)
        }
        if !hasBeenPositioned {
            hasBeenPositioned = true
            positionWindow(window)
        }

        // The app may run as an accessory (no Dock icon), so it has to be activated explicitly.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Restores the last position (keeping the size of the selected tab), or centers the window the first time.
    private func positionWindow(_ window: NSWindow) {
        let size = window.frame.size
        if window.setFrameUsingName(Self.frameAutosaveName) {
            let saved = window.frame
            window.setFrame(
                NSRect(x: saved.minX, y: saved.maxY - size.height, width: size.width, height: size.height),
                display: false
            )
        } else {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
    }

    /// Re-activates the app after its activation policy changed (showing/hiding the Dock icon can
    /// deactivate the app and send the window behind other apps).
    func bringBackAfterActivationPolicyChange() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, window.isVisible else { return }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Tab View Controller

/// Toolbar-style tab controller: one SwiftUI hosting controller per tab, window title = selected tab,
/// window height animated to fit the selected tab.
final class SettingsTabViewController: NSTabViewController {
    private static let selectedTabKey = "SettingsSelectedTab"

    /// Natural content size of each tab, as last reported by its `SettingsTabContainer`.
    private var measuredSizes: [SettingsTab: CGSize] = [:]

    init(model: SettingsModel) {
        super.init(nibName: nil, bundle: nil)

        tabStyle = .toolbar
        transitionOptions = [.crossfade, .allowUserInteraction]

        for tab in SettingsTab.allCases {
            let controller = makeController(for: tab, model: model)
            controller.title = tab.title

            let item = NSTabViewItem(viewController: controller)
            item.identifier = tab.rawValue
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: nil)
            addTabViewItem(item)
        }

        if let saved = UserDefaults.standard.string(forKey: Self.selectedTabKey),
           let index = SettingsTab.allCases.firstIndex(where: { $0.rawValue == saved }) {
            selectedTabViewItemIndex = index
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeController(for tab: SettingsTab, model: SettingsModel) -> NSViewController {
        switch tab {
        case .general: hostingController(for: tab, GeneralSettingsView(model: model))
        case .capture: hostingController(for: tab, CaptureSettingsView(model: model))
        case .shortcuts: hostingController(for: tab, ShortcutsSettingsView(model: model))
        case .about: hostingController(for: tab, AboutSettingsView())
        }
    }

    private func hostingController<Content: View>(for tab: SettingsTab, _ content: Content) -> NSViewController {
        let container = SettingsTabContainer(
            onSizeChange: { [weak self] size in
                self?.contentSizeDidChange(size, in: tab)
            },
            content: content
        )
        let controller = NSHostingController(rootView: container)
        // `preferredContentSize` is a fallback for the very first display; size changes are reported
        // right away by `SettingsTabContainer` (the hosting controller only updates its preferred size
        // on the next layout pass). No Auto Layout constraints: the window frame is driven from here.
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }

    private var selectedTab: SettingsTab? {
        guard SettingsTab.allCases.indices.contains(selectedTabViewItemIndex) else { return nil }
        return SettingsTab.allCases[selectedTabViewItemIndex]
    }

    private var selectedViewController: NSViewController? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return tabViewItems[selectedTabViewItemIndex].viewController
    }

    // MARK: Selection

    override func viewWillAppear() {
        super.viewWillAppear()
        updateWindowTitle()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)

        if let identifier = tabViewItem?.identifier as? String {
            UserDefaults.standard.set(identifier, forKey: Self.selectedTabKey)
        }
        updateWindowTitle()
        fitWindowToSelectedTab(animated: true)
    }

    private func updateWindowTitle() {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return }
        view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }

    // MARK: Sizing

    /// A tab's content changed size (e.g. a footer appeared): follow it if that tab is visible.
    private func contentSizeDidChange(_ size: CGSize, in tab: SettingsTab) {
        guard size.width > 0, size.height > 0, measuredSizes[tab] != size else { return }
        measuredSizes[tab] = size
        if tab == selectedTab {
            fitWindowToSelectedTab(animated: view.window?.isVisible == true)
        }
    }

    /// Resizes the window to the selected tab's natural size, keeping its top edge in place.
    func fitWindowToSelectedTab(animated: Bool) {
        guard let window = view.window, let controller = selectedViewController else { return }

        // Make sure SwiftUI measured the content at least once.
        controller.view.layoutSubtreeIfNeeded()
        let contentSize = selectedTab.flatMap { measuredSizes[$0] } ?? controller.preferredContentSize
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        let chromeHeight = window.frame.height - window.contentLayoutRect.height
        let newSize = NSSize(width: contentSize.width, height: (contentSize.height + chromeHeight).rounded())
        let oldFrame = window.frame
        guard newSize != oldFrame.size else { return }

        let newFrame = NSRect(
            x: oldFrame.minX,
            y: oldFrame.maxY - newSize.height,
            width: newSize.width,
            height: newSize.height
        )

        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = window.animationResizeTime(newFrame)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }
}
