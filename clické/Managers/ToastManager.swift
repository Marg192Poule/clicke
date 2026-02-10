import AppKit
import SwiftUI

/// Manager for displaying toast notifications.
/// Uses a singleton pattern to ensure only one toast is shown at a time.
class ToastManager {
    
    // MARK: - Singleton
    
    static let shared = ToastManager()
    
    // MARK: - Properties
    
    private var popupWindow: NSWindow?
    private var dismissWorkItem: DispatchWorkItem?
    
    // MARK: - Show Toast
    
    /// Shows a simple toast notification.
    /// - Parameters:
    ///   - message: The message to display.
    ///   - icon: The SF Symbol name for the icon.
    ///   - success: Whether this is a success or error toast.
    func show(message: String, icon: String, success: Bool) {
        popupWindow?.close()
        dismissWorkItem?.cancel()

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let window = NSPanel(
            contentRect: screen.frame,
            styleMask: [.fullSizeContentView, .borderless, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary, .ignoresCycle]

        let toastView = ToastView(message: message, icon: icon, success: success)
        let centeredToast = VStack {
            toastView
                .padding(.top, 50)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        
        window.contentView = NSHostingView(rootView: centeredToast)

        // Fade in animation
        window.alphaValue = 0
        window.orderFront(nil)
        popupWindow = window

        NSAnimationContext.runAnimationGroup { context in 
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in 
            NSAnimationContext.runAnimationGroup({ context in 
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            }) {
                window.close()
                self?.popupWindow = nil
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

    /// Shows an interactive toast with an Edit button.
    /// - Parameters:
    ///   - message: The message to display.
    ///   - icon: The SF Symbol name for the icon.
    ///   - screenshotImage: The captured image to edit.
    func showWithEditOption(message: String, icon: String, screenshotImage: NSImage) {
        popupWindow?.close()
        dismissWorkItem?.cancel()

        let screen = NSScreen.main ?? NSScreen.screens[0]

        // Compact toast dimensions - only covers the toast area, not the full screen
        let toastWidth: CGFloat = 280
        let toastHeight: CGFloat = 52
        let toastX = screen.frame.midX - toastWidth / 2
        let toastY = screen.frame.maxY - toastHeight - 50
        let toastRect = NSRect(x: toastX, y: toastY, width: toastWidth, height: toastHeight)

        let window = NSPanel(
            contentRect: toastRect,
            styleMask: [.fullSizeContentView, .borderless, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary, .ignoresCycle]

        let capturedImage = screenshotImage

        let toastView = InteractiveToastView(
            message: message,
            icon: icon,
            onEdit: { [weak self] in
                self?.dismiss()
                ScreenshotEditorWindow.shared.show(with: capturedImage)
            }
        )

        window.contentView = NSHostingView(rootView: toastView)

        // Fade in animation
        window.alphaValue = 0
        window.orderFront(nil)
        popupWindow = window

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        // Auto-dismiss after 3 seconds
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    /// Dismisses the currently displayed toast.
    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        
        guard let window = popupWindow else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }) { [weak self] in
            window.close()
            self?.popupWindow = nil
        }
    }
}
