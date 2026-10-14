import AppKit

// MARK: - Capture Mode

/// The kinds of capture Clické performs with `/usr/sbin/screencapture`.
enum CaptureMode: CaseIterable {
    /// Interactive selection of a screen area (Space switches to window selection).
    case area
    /// Interactive selection of a single window.
    case window
    /// The whole display under the mouse pointer.
    case fullScreen

    /// Title used in menus.
    var title: String {
        switch self {
        case .area: String(localized: "Capture Area")
        case .window: String(localized: "Capture Window")
        case .fullScreen: String(localized: "Capture Full Screen")
        }
    }

    /// SF Symbol shown next to the menu item.
    var symbolName: String {
        switch self {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .fullScreen: "display"
        }
    }

    /// The shortcut assigned to this mode (`nil` = disabled).
    func hotkey(in settings: AppSettings) -> HotkeyConfiguration? {
        switch self {
        case .area: settings.areaHotkey
        case .window: settings.windowHotkey
        case .fullScreen: settings.fullScreenHotkey
        }
    }

    /// `screencapture` options for this mode (the output file is appended by the caller).
    ///
    /// - `-x`: no system sound, Clické plays its own (if enabled in Settings).
    /// - `-t png`: lossless, keeps transparency and the Retina DPI metadata.
    /// - `-o`: no system window shadow. The editor adds its own shadow and background; the system
    ///   shadow would add a wide transparent margin around window captures (off-center layouts,
    ///   double shadows). It only affects window selection, so it's also passed in area mode
    ///   where Space toggles window selection.
    var screencaptureArguments: [String] {
        let common = ["-x", "-t", "png"]
        switch self {
        case .area:
            return common + ["-i", "-o"]
        case .window:
            return common + ["-i", "-w", "-o"]
        case .fullScreen:
            let index = ScreenLocator.screencaptureDisplayIndex(for: ScreenLocator.screenUnderPointer())
            return common + ["-D", String(index)]
        }
    }
}
