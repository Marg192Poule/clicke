import AppKit
import SwiftUI

class ScreenshotEditorWindow: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private var editorWindow: NSWindow?
    private var isClosing = false
    
    static let shared = ScreenshotEditorWindow()
    
    // Toolbar item identifiers
    private struct ToolbarIdentifiers {
        static let toolbar = NSToolbar.Identifier("ScreenshotEditorToolbar")
        static let copyItem = NSToolbarItem.Identifier("CopyItem")
        static let saveItem = NSToolbarItem.Identifier("SaveItem")
        static let resetItem = NSToolbarItem.Identifier("ResetItem")
        static let zoomFit = NSToolbarItem.Identifier("ZoomFitItem")
        static let zoomActual = NSToolbarItem.Identifier("ZoomActualItem")
        static let flexibleSpace = NSToolbarItem.Identifier.flexibleSpace
        static let space = NSToolbarItem.Identifier.space
    }
    
    // Notification names for toolbar actions
    static let copyNotification = Notification.Name("ScreenshotEditorToolbarCopy")
    static let saveNotification = Notification.Name("ScreenshotEditorToolbarSave")
    static let resetNotification = Notification.Name("ScreenshotEditorToolbarReset")
    static let zoomFitNotification = Notification.Name("ScreenshotEditorToolbarZoomFit")
    static let zoomActualNotification = Notification.Name("ScreenshotEditorToolbarZoomActual")
    static let miniaturizeNotification = Notification.Name("ScreenshotEditorMiniaturize")
    static let zoomWindowNotification = Notification.Name("ScreenshotEditorZoomWindow")
    
    private override init() {
        super.init()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleMiniaturize), name: Self.miniaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleZoomWindow), name: Self.zoomWindowNotification, object: nil)
    }
    
    @objc private func handleMiniaturize() {
        editorWindow?.miniaturize(nil)
    }
    
    @objc private func handleZoomWindow() {
        editorWindow?.zoom(nil)
    }
    
    func show(with image: NSImage) {
        // Close any existing window first
        if editorWindow != nil {
            closeImmediately()
        }
        
        isClosing = false
        createWindow(with: image)
    }
    
    private func closeImmediately() {
        guard let window = editorWindow else { return }
        window.delegate = nil
        window.contentView = nil
        window.orderOut(nil)
        editorWindow = nil
    }
    
    private func createWindow(with image: NSImage) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let windowWidth = min(screen.frame.width * 0.9, 1600)
        let windowHeight = min(screen.frame.height * 0.9, 1000)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false
        )
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 800, height: 600)
        window.center()
        window.delegate = self
        
        // Remove toolbar separator for seamless look
        window.titlebarSeparatorStyle = .none
        
        // No custom toolbar - SwiftUI NavigationSplitView handles it
        
        editorWindow = window
        
        let editorView = ScreenshotEditorView(
            originalImage: image,
            onCopy: { [weak self] renderedImage in
                self?.copyAndClose(renderedImage)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
        
        window.contentView = NSHostingView(rootView: editorView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func copyAndClose(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        
        close()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            ToastManager().show(message: "Copied", icon: "doc.on.clipboard.fill", success: true)
        }
    }
    
    func close() {
        guard !isClosing, let window = editorWindow else { return }
        isClosing = true
        
        // Clear content view FIRST to release SwiftUI views
        window.contentView = nil
        window.delegate = nil
        
        // Close without animation to avoid memory issues
        window.orderOut(nil)
        editorWindow = nil
        isClosing = false
    }
    
    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        guard !isClosing else { return }
        isClosing = true
        
        if let window = editorWindow {
            window.contentView = nil
            window.delegate = nil
        }
        editorWindow = nil
        isClosing = false
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false // We handle closing manually
    }
    
    // MARK: - Toolbar Setup
    private func setupToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: ToolbarIdentifiers.toolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }
    
    // MARK: - NSToolbarDelegate
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarIdentifiers.copyItem:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Copy"
            item.paletteLabel = "Copy to Clipboard"
            item.toolTip = "Copy screenshot to clipboard"
            item.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Copy")
            item.target = self
            item.action = #selector(toolbarCopyAction)
            item.isBordered = true
            return item
            
        case ToolbarIdentifiers.saveItem:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Save"
            item.paletteLabel = "Save to File"
            item.toolTip = "Save screenshot to file"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
            item.target = self
            item.action = #selector(toolbarSaveAction)
            item.isBordered = true
            return item
            
        case ToolbarIdentifiers.resetItem:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Reset"
            item.paletteLabel = "Reset Position"
            item.toolTip = "Reset position and zoom"
            item.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset")
            item.target = self
            item.action = #selector(toolbarResetAction)
            item.isBordered = true
            return item
            
        case ToolbarIdentifiers.zoomFit:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Fit"
            item.paletteLabel = "Zoom to Fit"
            item.toolTip = "Fit screenshot in view"
            item.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Fit")
            item.target = self
            item.action = #selector(toolbarZoomFitAction)
            item.isBordered = true
            return item
            
        case ToolbarIdentifiers.zoomActual:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "100%"
            item.paletteLabel = "Actual Size"
            item.toolTip = "View at actual size"
            item.image = NSImage(systemSymbolName: "1.magnifyingglass", accessibilityDescription: "100%")
            item.target = self
            item.action = #selector(toolbarZoomActualAction)
            item.isBordered = true
            return item
            
        default:
            return nil
        }
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarIdentifiers.flexibleSpace,
            ToolbarIdentifiers.zoomFit,
            ToolbarIdentifiers.zoomActual,
            ToolbarIdentifiers.space,
            ToolbarIdentifiers.resetItem,
            ToolbarIdentifiers.space,
            ToolbarIdentifiers.saveItem,
            ToolbarIdentifiers.copyItem
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarIdentifiers.copyItem,
            ToolbarIdentifiers.saveItem,
            ToolbarIdentifiers.resetItem,
            ToolbarIdentifiers.zoomFit,
            ToolbarIdentifiers.zoomActual,
            ToolbarIdentifiers.flexibleSpace,
            ToolbarIdentifiers.space
        ]
    }
    
    // MARK: - Toolbar Actions
    @objc private func toolbarCopyAction() {
        NotificationCenter.default.post(name: Self.copyNotification, object: nil)
    }
    
    @objc private func toolbarSaveAction() {
        NotificationCenter.default.post(name: Self.saveNotification, object: nil)
    }
    
    @objc private func toolbarResetAction() {
        NotificationCenter.default.post(name: Self.resetNotification, object: nil)
    }
    
    @objc private func toolbarZoomFitAction() {
        NotificationCenter.default.post(name: Self.zoomFitNotification, object: nil)
    }
    
    @objc private func toolbarZoomActualAction() {
        NotificationCenter.default.post(name: Self.zoomActualNotification, object: nil)
    }
}