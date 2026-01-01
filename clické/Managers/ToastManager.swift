// AppKit (low level) == (NSWindow, NSPanel) -> native windows , 
// (NSScreen) -> infos windows, 
// (all the enums) -> ex: isOpaque, .buffered, etc...
import AppKit
// SwiftUI (high level) == modern UI native
// ex -> 
// VStack, padding, NSHostingView = AppKit stack SwiftUI view, etc...
import SwiftUI

class ToastManager {
    private var popupWindow: NSWindow? // display window or nil
    private var dismissWorkItem: DispatchWorkItem? // programmable task, we can exec, stop, override

    func show(message: String, icon: String, success: Bool) {
        popupWindow?.close() // close if already open
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
            Spacer() // transparente zone for the rest
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        
        window.contentView = NSHostingView(rootView: centeredToast)

        // animation
        window.alphaValue = 0
        window.orderFront(nil)
        popupWindow = window // save the ref, for closing later

        NSAnimationContext.runAnimationGroup { context in 
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        //let workItem
    }
}