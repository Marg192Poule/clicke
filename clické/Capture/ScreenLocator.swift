import AppKit
import CoreGraphics

// MARK: - Screen Locator

/// Finds displays relative to the mouse pointer, so captures, previews and toasts appear
/// where the user is looking rather than always on the main display.
enum ScreenLocator {
    /// The screen containing the mouse pointer (falls back to the main screen).
    static func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// The Core Graphics display ID of `screen`.
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    /// The screen showing the display `displayID`, if it's still connected.
    static func screen(withDisplayID displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { self.displayID(of: $0) == displayID }
    }

    /// The `screencapture -D` index of `screen`.
    ///
    /// `screencapture` numbers displays from 1 in `CGGetActiveDisplayList` order (1 = main display).
    /// Falls back to 1 when the display can't be found.
    static func screencaptureDisplayIndex(for screen: NSScreen?) -> Int {
        guard let screen, let displayID = displayID(of: screen) else { return 1 }

        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 1 }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return 1 }

        guard let index = displays.prefix(Int(count)).firstIndex(of: displayID) else { return 1 }
        return index + 1
    }
}
