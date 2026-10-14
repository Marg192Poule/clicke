import AppKit
import SwiftUI

/// Manages the screenshot editor window.
///
/// There is a single editor window: showing an image while it's open adds the image as a new layer.
final class ScreenshotEditorWindow: NSObject, NSWindowDelegate {
    static let shared = ScreenshotEditorWindow()

    private var window: EditorWindow?
    private var model: ScreenshotEditorViewModel?
    private var toolbarController: EditorToolbarController?

    private static let frameAutosaveName = "ClickeEditorWindow"

    private override init() {
        super.init()
    }

    /// Whether the editor window is currently open.
    var isOpen: Bool { window != nil }

    /// Opens the editor with `image`, or adds it as a new layer if the editor is already open.
    func show(with image: NSImage) {
        show(with: [image])
    }

    /// Opens the editor with `images` as layers, or adds them to the open editor.
    func show(with images: [NSImage]) {
        guard !images.isEmpty else { return }

        if let window, let model {
            images.forEach { model.addImage($0) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        createWindow(with: images)
    }

    /// Closes the editor window.
    func close() {
        window?.performClose(nil)
    }

    /// Whether the open editor holds edits that were never copied, saved or dragged out.
    /// (Contract for the app delegate's quit confirmation; implemented by the editor.)
    var hasUnexportedChanges: Bool { false }

    /// Asks the user what to do with unexported edits (Save… / Don't Save / Cancel) if there are any.
    /// Calls `completion(true)` when it's fine to close/quit, `false` if the user cancelled.
    func confirmDiscardingChanges(_ completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    // MARK: - Window

    private func createWindow(with images: [NSImage]) {
        let model = ScreenshotEditorViewModel(images: images)

        let window = EditorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = String(localized: "Clické Editor")
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 760, height: 520)

        // Restore the last frame, or use 85% of the screen (up to 1600 × 1000).
        // Done before the content is set, so SwiftUI lays the editor out once, at its final size.
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let size = NSSize(width: min(visible.width * 0.85, 1600), height: min(visible.height * 0.85, 1000))
            window.setFrame(NSRect(origin: .zero, size: size), display: false)
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)

        let hostingController = NSHostingController(rootView: ScreenshotEditorView(model: model))
        hostingController.sceneBridgingOptions = []
        hostingController.sizingOptions = []
        hostingController.view.frame = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        window.contentViewController = hostingController
        window.delegate = self
        window.commandHandler = { [weak model] command in
            model?.perform(command) ?? false
        }

        let toolbarController = EditorToolbarController(model: model)
        toolbarController.window = window
        window.toolbar = toolbarController.toolbar

        model.window = window
        self.window = window
        self.model = model
        self.toolbarController = toolbarController

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? EditorWindow, closing === window else { return }
        model?.editorWillClose()
        // Release the SwiftUI hierarchy and the images right away.
        closing.commandHandler = nil
        closing.contentViewController = nil
        closing.delegate = nil
        closing.toolbar = nil
        window = nil
        model = nil
        toolbarController = nil
    }
}

// MARK: - Editor Window

/// The editor's window. It handles the editor's keyboard shortcuts itself, so they work even
/// when the app has no menu bar (menu bar app / accessory mode).
final class EditorWindow: NSWindow {
    /// Performs an editor command; returns `false` if it didn't apply.
    var commandHandler: ((EditorCommand) -> Bool)?

    /// A text field is being edited: leave standard editing keys (⌘C, ⌘Z, arrows…) to it.
    private var isEditingText: Bool {
        firstResponder is NSText
    }

    // MARK: ⌘ Shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let command = keyEquivalentCommand(for: event), commandHandler?(command) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func keyEquivalentCommand(for event: NSEvent) -> EditorCommand? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.contains(.command), !modifiers.contains(.control),
              let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        let shift = modifiers.contains(.shift)
        let option = modifiers.contains(.option)

        switch key {
        case "w" where !shift && !option: return .close
        case "s" where !option: return .save
        case "o" where !shift && !option: return .addImage
        case "i" where option && !shift: return .toggleInspector
        case "c" where !shift && !option && !isEditingText: return .copy
        case "z" where !option && !isEditingText: return shift ? .redo : .undo
        case "=", "+": return .zoomIn
        case "-", "_": return .zoomOut
        case "0" where !shift && !option: return .zoomToFit
        case "1" where !shift && !option: return .actualSize
        default: return nil
        }
    }

    // MARK: Plain Keys

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, attachedSheet == nil, !isEditingText,
           let command = plainKeyCommand(for: event), commandHandler?(command) == true {
            return
        }
        super.sendEvent(event)
    }

    private func plainKeyCommand(for event: NSEvent) -> EditorCommand? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return nil }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1

        switch Int(event.keyCode) {
        case 51, 117: return .deleteSelection // ⌫, ⌦
        case 53: return .deselect // Esc
        case 123: return .nudge(dx: -step, dy: 0)
        case 124: return .nudge(dx: step, dy: 0)
        case 125: return .nudge(dx: 0, dy: step)
        case 126: return .nudge(dx: 0, dy: -step)
        default: return nil
        }
    }

    // MARK: Menu Actions

    // When the app shows its menu bar, Edit and File menu items reach the editor through the responder chain.

    @objc func copy(_ sender: Any?) {
        _ = commandHandler?(.copy)
    }

    @objc func undo(_ sender: Any?) {
        _ = commandHandler?(.undo)
    }

    @objc func redo(_ sender: Any?) {
        _ = commandHandler?(.redo)
    }

    @objc func saveDocument(_ sender: Any?) {
        _ = commandHandler?(.save)
    }
}
