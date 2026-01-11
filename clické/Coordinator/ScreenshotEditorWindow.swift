import AppKit
import SwiftUI

/// Manages the screenshot editor window lifecycle and presentation.
class ScreenshotEditorWindow: NSObject, NSWindowDelegate {
    private var editorWindow: NSWindow?
    private var isClosing = false
    
    static let shared = ScreenshotEditorWindow()
    
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
    
    /// Shows the editor window with the specified image.
    /// - Parameter image: The screenshot image to edit.
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
            ToastManager.shared.show(message: "Copied", icon: "doc.on.clipboard.fill", success: true)
        }
    }
    
    /// Closes the editor window.
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
}
