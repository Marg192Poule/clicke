import AppKit
import Carbon.HIToolbox

/// Builds Clické's menus (menu bar extra, main menu, Dock menu) and handles their commands.
///
/// Capture items show their shortcut only while it's actually active (registered as a global hot
/// key); they're refreshed whenever settings or shortcut availability change. The editor's
/// commands (Save, Undo, Zoom, Inspector…) are first-responder actions implemented by its window.
final class MenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    static let shared = MenuController()

    private static let appName = "Clické"
    private static let projectURL = URL(string: "https://github.com/nathbns/clicke")!
    private static let helpURL = URL(string: "https://github.com/nathbns/clicke#readme")!

    /// Capture items of the menu bar extra and of the File menu, kept in sync with the shortcuts.
    private var captureItems: [NSMenuItem] = []

    /// "Show Editor" in the menu bar extra, only visible while the editor is open.
    private var showEditorItem: NSMenuItem?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyAvailabilityDidChange),
            name: .hotkeyAvailabilityDidChange,
            object: nil
        )
    }

    // MARK: - Menu Bar Extra

    /// Creates the menu bar extra (status item) and its menu.
    func makeStatusItem() -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "ClickeStatusItem"

        if let button = statusItem.button {
            let configuration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
            let image = NSImage(systemSymbolName: "c.square.fill", accessibilityDescription: Self.appName)?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = true
            button.image = image
            button.toolTip = Self.appName
        }

        let menu = NSMenu()
        menu.autoenablesItems = false   // enabled states are set in `menuNeedsUpdate(_:)`
        menu.delegate = self
        CaptureMode.allCases.forEach { menu.addItem(makeCaptureItem($0)) }
        menu.addItem(.separator())

        let showEditorItem = makeItem(String(localized: "Show Editor"), symbol: "macwindow.on.rectangle", action: #selector(showEditor(_:)))
        showEditorItem.isHidden = true
        menu.addItem(showEditorItem)
        self.showEditorItem = showEditorItem

        addImageItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "About \(Self.appName)"), symbol: "info.circle", action: #selector(showAbout(_:))))
        menu.addItem(makeItem(String(localized: "Settings…"), symbol: "gearshape", action: #selector(showSettings(_:)), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Quit \(Self.appName)"), symbol: "power", action: #selector(NSApplication.terminate(_:)), key: "q", target: .application))
        statusItem.menu = menu

        return statusItem
    }

    // MARK: - Main Menu

    /// The application's main menu. It's visible whenever Clické shows in the Dock (always, or
    /// while one of its windows is open); its key equivalents also work in Clické's windows.
    func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        addSubmenu(makeAppMenu(), to: mainMenu)
        addSubmenu(makeFileMenu(), to: mainMenu)
        addSubmenu(makeEditMenu(), to: mainMenu)
        addSubmenu(makeViewMenu(), to: mainMenu)

        let windowMenu = makeWindowMenu()
        addSubmenu(windowMenu, to: mainMenu)
        NSApp.windowsMenu = windowMenu

        let helpMenu = makeHelpMenu()
        addSubmenu(helpMenu, to: mainMenu)
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    private func makeAppMenu() -> NSMenu {
        let menu = NSMenu(title: Self.appName)
        menu.addItem(makeItem(String(localized: "About \(Self.appName)"), action: #selector(showAbout(_:))))
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Settings…"), action: #selector(showSettings(_:)), key: ","))
        menu.addItem(.separator())
        let servicesMenu = NSMenu(title: String(localized: "Services"))
        let servicesItem = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Hide \(Self.appName)"), action: #selector(NSApplication.hide(_:)), key: "h", target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), target: .firstResponder))
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Quit \(Self.appName)"), action: #selector(NSApplication.terminate(_:)), key: "q", target: .firstResponder))
        return menu
    }

    private func makeFileMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "File"))
        menu.delegate = self
        CaptureMode.allCases.forEach { menu.addItem(makeCaptureItem($0)) }
        menu.addItem(.separator())
        addImageItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), key: "w", target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Save…"), action: #selector(NSDocument.save(_:)), key: "s", target: .firstResponder))
        return menu
    }

    /// Standard responder-chain actions: the editor implements them, and text fields get ⌘C/⌘V/⌘Z.
    private func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit"))
        menu.addItem(makeItem(String(localized: "Undo"), action: Selector(("undo:")), key: "z", target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Redo"), action: Selector(("redo:")), key: "z", modifiers: [.command, .shift], target: .firstResponder))
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Cut"), action: #selector(NSText.cut(_:)), key: "x", target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Copy"), action: #selector(NSText.copy(_:)), key: "c", target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Paste"), action: #selector(NSText.paste(_:)), key: "v", target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Delete"), action: #selector(NSText.delete(_:)), target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), key: "a", target: .firstResponder))
        return menu
    }

    /// Editor view commands. The actions are implemented by the editor window (disabled elsewhere);
    /// it also retitles "Show Inspector" / "Hide Inspector" when validating the item.
    private func makeViewMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "View"))
        let zoomInTitle = String(localized: "Zoom In")
        menu.addItem(makeItem(zoomInTitle, action: Selector(("zoomIn:")), key: "+", target: .firstResponder))
        // ⌘= also zooms in (no Shift needed on most layouts), without a second visible item.
        let zoomInAlternate = makeItem(zoomInTitle, action: Selector(("zoomIn:")), key: "=", target: .firstResponder)
        zoomInAlternate.isHidden = true
        zoomInAlternate.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInAlternate)
        menu.addItem(makeItem(String(localized: "Zoom Out"), action: Selector(("zoomOut:")), key: "-", target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Actual Size"), action: Selector(("zoomToActualSize:")), key: "0", target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Zoom to Fit"), action: Selector(("zoomToFit:")), key: "9", target: .firstResponder))
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Show Inspector"), action: #selector(NSSplitViewController.toggleInspector(_:)), key: "i", modifiers: [.command, .option], target: .firstResponder))
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Enter Full Screen"), action: #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control], target: .firstResponder))
        return menu
    }

    private func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Window"))
        menu.addItem(makeItem(String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), key: "m", target: .firstResponder))
        menu.addItem(makeItem(String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), target: .firstResponder))
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), target: .firstResponder))
        return menu
    }

    private func makeHelpMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Help"))
        menu.addItem(makeItem(String(localized: "\(Self.appName) Help"), action: #selector(showHelp(_:)), key: "?"))
        return menu
    }

    // MARK: - Dock Menu

    /// Capture commands for the Dock icon's menu.
    func makeDockMenu() -> NSMenu {
        let menu = NSMenu()
        for mode in CaptureMode.allCases {
            menu.addItem(makeItem(mode.title, action: #selector(capture(_:)), tag: mode.menuTag))
        }
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Open Image…"), action: #selector(openImage(_:))))
        return menu
    }

    // MARK: - Shortcuts

    /// Updates the shortcut shown by every capture item from the current settings.
    func refreshShortcuts() {
        let settings = AppSettings.current
        for item in captureItems {
            guard let mode = CaptureMode(menuTag: item.tag) else { continue }
            applyShortcut(mode.hotkey(in: settings), to: item)
        }
    }

    @objc private func hotkeyAvailabilityDidChange() {
        refreshShortcuts()
    }

    private func applyShortcut(_ hotkey: HotkeyConfiguration?, to item: NSMenuItem) {
        // Only active shortcuts are shown: an unregistered one would either do nothing, or only
        // work while Clické is the active app (as a menu key equivalent), which would be misleading.
        guard let hotkey,
              hotkey.isValidGlobalShortcut,
              !HotkeyAvailability.unavailable.contains(hotkey),
              let key = Self.keyEquivalent(for: hotkey) else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = hotkey.modifiers
    }

    /// The `NSMenuItem` key equivalent for a shortcut's key, in the current keyboard layout.
    private static func keyEquivalent(for hotkey: HotkeyConfiguration) -> String? {
        let keyCode = Int(hotkey.keyCode)

        let functionKeys: [Int: Int] = [
            kVK_F1: NSF1FunctionKey, kVK_F2: NSF2FunctionKey, kVK_F3: NSF3FunctionKey, kVK_F4: NSF4FunctionKey,
            kVK_F5: NSF5FunctionKey, kVK_F6: NSF6FunctionKey, kVK_F7: NSF7FunctionKey, kVK_F8: NSF8FunctionKey,
            kVK_F9: NSF9FunctionKey, kVK_F10: NSF10FunctionKey, kVK_F11: NSF11FunctionKey, kVK_F12: NSF12FunctionKey,
            kVK_F13: NSF13FunctionKey, kVK_F14: NSF14FunctionKey, kVK_F15: NSF15FunctionKey, kVK_F16: NSF16FunctionKey,
            kVK_F17: NSF17FunctionKey, kVK_F18: NSF18FunctionKey, kVK_F19: NSF19FunctionKey, kVK_F20: NSF20FunctionKey,
            kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
            kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey,
            kVK_Home: NSHomeFunctionKey, kVK_End: NSEndFunctionKey,
            kVK_PageUp: NSPageUpFunctionKey, kVK_PageDown: NSPageDownFunctionKey,
            kVK_ForwardDelete: NSDeleteFunctionKey, kVK_Help: NSHelpFunctionKey
        ]
        if let functionKey = functionKeys[keyCode], let scalar = Unicode.Scalar(UInt32(functionKey)) {
            return String(Character(scalar))
        }

        let controlKeys: [Int: String] = [
            kVK_Return: "\r", kVK_ANSI_KeypadEnter: "\u{3}", kVK_Tab: "\t",
            kVK_Space: " ", kVK_Delete: "\u{8}", kVK_Escape: "\u{1b}"
        ]
        if let key = controlKeys[keyCode] {
            return key
        }

        // Character keys: the character printed on the key in the current layout.
        let name = HotkeyConfiguration.displayName(for: hotkey.keyCode)
        guard name.count == 1 else { return nil }
        return name.lowercased()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshShortcuts()
        showEditorItem?.isHidden = !ScreenshotEditorWindow.shared.isOpen
        guard !menu.autoenablesItems else { return }   // auto-enabled menus use `validateMenuItem(_:)`
        for item in menu.items where item.action != nil {
            item.isEnabled = isEnabled(item.action)
        }
    }

    // MARK: - NSMenuItemValidation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        isEnabled(menuItem.action)
    }

    private func isEnabled(_ action: Selector?) -> Bool {
        switch action {
        case #selector(editClipboardImage(_:)):
            return CaptureController.shared.clipboardHasImage
        case #selector(editLastCapture(_:)):
            return CaptureController.shared.lastCapture != nil
        case #selector(showEditor(_:)):
            return ScreenshotEditorWindow.shared.isOpen
        default:
            return true
        }
    }

    // MARK: - Actions

    @objc func capture(_ sender: NSMenuItem) {
        guard let mode = CaptureMode(menuTag: sender.tag) else { return }
        // Let the menu close before an interactive capture starts.
        DispatchQueue.main.async {
            CaptureController.shared.capture(mode)
        }
    }

    @objc func openImage(_ sender: Any?) {
        CaptureController.shared.presentOpenPanel()
    }

    @objc func editClipboardImage(_ sender: Any?) {
        CaptureController.shared.editClipboardImage()
    }

    @objc func editLastCapture(_ sender: Any?) {
        CaptureController.shared.editLastCapture()
    }

    @objc func showEditor(_ sender: Any?) {
        ScreenshotEditorWindow.shared.bringToFront()
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: Self.appName,
            .credits: Self.aboutCredits
        ])
    }

    @objc func showHelp(_ sender: Any?) {
        NSWorkspace.shared.open(Self.helpURL)
    }

    /// The About panel's credits: the project page and the license.
    private static var aboutCredits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        var linkAttributes = attributes
        linkAttributes[.link] = projectURL

        let credits = NSMutableAttributedString(string: "github.com/nathbns/clicke", attributes: linkAttributes)
        credits.append(NSAttributedString(string: "\n" + String(localized: "Released under the MIT License"), attributes: attributes))
        return credits
    }

    // MARK: - Item Factories

    private func makeCaptureItem(_ mode: CaptureMode) -> NSMenuItem {
        let item = makeItem(mode.title, symbol: mode.symbolName, action: #selector(capture(_:)), tag: mode.menuTag)
        applyShortcut(mode.hotkey(in: AppSettings.current), to: item)
        captureItems.append(item)
        return item
    }

    private func addImageItems(to menu: NSMenu) {
        menu.addItem(makeItem(String(localized: "Open Image…"), symbol: "photo", action: #selector(openImage(_:)), key: "o"))
        menu.addItem(makeItem(String(localized: "Edit Clipboard Image"), symbol: "doc.on.clipboard", action: #selector(editClipboardImage(_:))))
        menu.addItem(makeItem(String(localized: "Edit Last Screenshot"), symbol: "clock.arrow.circlepath", action: #selector(editLastCapture(_:))))
    }

    /// Who receives a menu item's action.
    private enum ItemTarget {
        /// This controller (Clické's own commands).
        case controller
        /// The first responder implementing the action (standard App/Edit/Window items, editor commands).
        case firstResponder
        /// `NSApp` itself.
        case application
    }

    private func makeItem(
        _ title: String,
        symbol: String? = nil,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        tag: Int = 0,
        target: ItemTarget = .controller
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag
        switch target {
        case .controller: item.target = self
        case .firstResponder: item.target = nil
        case .application: item.target = NSApp
        }
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}

// MARK: - Menu Tags

private extension CaptureMode {
    var menuTag: Int {
        switch self {
        case .area: 1
        case .window: 2
        case .fullScreen: 3
        }
    }

    init?(menuTag: Int) {
        guard let mode = CaptureMode.allCases.first(where: { $0.menuTag == menuTag }) else { return nil }
        self = mode
    }
}
