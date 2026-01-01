import AppKit
import SwiftUI

class ScreenshotEditorWindow: NSObject, NSWindowDelegate {
    private var editorWindow: NSWindow?
    private var isClosing = false
    
    static let shared = ScreenshotEditorWindow()
    
    private override init() {
        super.init()
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
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        window.isMovableByWindowBackground = false // Disable window drag from content
        window.minSize = NSSize(width: 800, height: 600)
        window.center()
        window.delegate = self
        
        // Hide the standard window buttons (traffic lights) - we have our own
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
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
}