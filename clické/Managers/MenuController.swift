import AppKit
import Carbon.HIToolbox

/// Builds Clické's menus (menu bar extra, main menu, Dock menu) and handles their commands.
///
/// Capture items show the shortcut configured in Settings; it's refreshed whenever settings change.
final class MenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    static let shared = MenuController()

    private static let appName = "Clické"

    /// Capture items of the menu bar extra and of the File menu, kept in sync with the shortcuts.
    private var captureItems: [NSMenuItem] = []

    private override init() {
        super.init()
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
        addImageItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Settings…"), symbol: "gearshape", action: #selector(showSettings(_:)), key: ","))
        menu.addItem(makeItem(String(localized: "Quit \(Self.appName)"), symbol: "power", action: #selector(NSApplication.terminate(_:)), key: "q", target: .application))
        statusItem.menu = menu

        return statusItem
    }

    // MARK: - Main Menu

    /// The application's main menu (shown when the Dock icon is visible; its key equivalents
    /// also work in Clické's windows when it runs as a menu bar app).
    func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu(title: Self.appName)
        appMenu.addItem(makeItem(String(localized: "About \(Self.appName)"), action: #selector(showAbout(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem(String(localized: "Settings…"), action: #selector(showSettings(_:)), key: ","))
        appMenu.addItem(.separator())
        let servicesMenu = NSMenu(title: String(localized: "Services"))
        let servicesItem = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem(String(localized: "Hide \(Self.appName)"), action: #selector(NSApplication.hide(_:)), key: "h", target: .firstResponder))
        appMenu.addItem(makeItem(String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], target: .firstResponder))
        appMenu.addItem(makeItem(String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), target: .firstResponder))
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem(String(localized: "Quit \(Self.appName)"), action: #selector(NSApplication.terminate(_:)), key: "q", target: .firstResponder))
        addSubmenu(appMenu, to: mainMenu)

        // File menu
        let fileMenu = NSMenu(title: String(localized: "File"))
        fileMenu.delegate = self
        CaptureMode.allCases.forEach { fileMenu.addItem(makeCaptureItem($0)) }
        fileMenu.addItem(.separator())
        addImageItems(to: fileMenu)
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeItem(String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), key: "w", target: .firstResponder))
        addSubmenu(fileMenu, to: mainMenu)

        // Edit menu (standard responder-chain actions, needed for ⌘C/⌘V/⌘Z in text fields)
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(makeItem(String(localized: "Undo"), action: Selector(("undo:")), key: "z", target: .firstResponder))
        editMenu.addItem(makeItem(String(localized: "Redo"), action: Selector(("redo:")), key: "z", modifiers: [.command, .shift], target: .firstResponder))
        editMenu.addItem(.separator())
        editMenu.addItem(makeItem(String(localized: "Cut"), action: #selector(NSText.cut(_:)), key: "x", target: .firstResponder))
        editMenu.addItem(makeItem(String(localized: "Copy"), action: #selector(NSText.copy(_:)), key: "c", target: .firstResponder))
        editMenu.addItem(makeItem(String(localized: "Paste"), action: #selector(NSText.paste(_:)), key: "v", target: .firstResponder))
        editMenu.addItem(makeItem(String(localized: "Paste and Match Style"), action: #selector(NSTextView.pasteAsPlainText(_:)), key: "v", modifiers: [.command, .option, .shift], target: .firstResponder))
        editMenu.addItem(makeItem(String(localized: "Delete"), action: #selector(NSText.delete(_:)), target: .firstResponder))
        editMenu.addItem(makeItem(String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), key: "a", target: .firstResponder))
        addSubmenu(editMenu, to: mainMenu)

        // Window menu
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(makeItem(String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), key: "m", target: .firstResponder))
        windowMenu.addItem(makeItem(String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), target: .firstResponder))
        windowMenu.addItem(.separator())
        windowMenu.addItem(makeItem(String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), target: .firstResponder))
        addSubmenu(windowMenu, to: mainMenu)
        NSApp.windowsMenu = windowMenu

        return mainMenu
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

    private func applyShortcut(_ hotkey: HotkeyConfiguration?, to item: NSMenuItem) {
        // Only shortcuts that are registered globally are shown (and usable as key equivalents).
        guard let hotkey, hotkey.isValidGlobalShortcut, let key = Self.keyEquivalent(for: hotkey) else {
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

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: Self.appName])
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
        menu.addItem(makeItem(String(localized: "Edit Last Capture"), symbol: "clock.arrow.circlepath", action: #selector(editLastCapture(_:))))
    }

    /// Who receives a menu item's action.
    private enum ItemTarget {
        /// This controller (Clické's own commands).
        case controller
        /// The first responder implementing the action (standard App/Edit/Window items).
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
