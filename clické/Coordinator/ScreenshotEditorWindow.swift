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

        if let model {
            model.addImages(images)
            bringToFront()
            return
        }

        // Images that can't be edited are reported by the model; don't open an empty editor.
        let model = ScreenshotEditorViewModel(images: images)
        guard model.hasContent else { return }
        createWindow(with: model)
    }

    /// Closes the editor window.
    func close() {
        window?.performClose(nil)
    }

    /// Brings the open editor window to the front without changing its document.
    func bringToFront() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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

    private func createWindow(with model: ScreenshotEditorViewModel) {
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
        window.collectionBehavior.insert(.fullScreenPrimary)

        // Restore the last frame, or use 85% of the screen under the pointer (up to 1600 × 1000).
        // Done before the content is set, so SwiftUI lays the editor out once, at its final size.
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            let visible = ScreenLocator.screenUnderPointer()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let size = NSSize(width: min(visible.width * 0.85, 1600), height: min(visible.height * 0.85, 1000))
            let origin = NSPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded())
            window.setFrame(NSRect(origin: origin, size: size), display: false)
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)

        let hostingController = NSHostingController(rootView: ScreenshotEditorView(model: model))
        hostingController.sceneBridgingOptions = []
        hostingController.sizingOptions = []
        hostingController.view.frame = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        window.contentViewController = hostingController
        window.delegate = self
        window.editor = model

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
        closing.editor = nil
        closing.contentViewController = nil
        closing.delegate = nil
        closing.toolbar = nil
        window = nil
        model = nil
        toolbarController = nil
    }
}

// MARK: - Editor Window

/// The editor's window. Menu commands (Save, Copy, Paste, Undo, zoom…) reach it through the
/// responder chain and are validated here; a few plain keys (arrows, Esc, ⌫) are handled directly.
final class EditorWindow: NSWindow {
    weak var editor: ScreenshotEditorViewModel?

    /// A text field is being edited: leave its keys (arrows, ⌫…) to it.
    private var isEditingText: Bool {
        firstResponder is NSText
    }

    // MARK: Plain Keys

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, attachedSheet == nil, !isEditingText,
           let editor, handlePlainKey(event, editor: editor) {
            return
        }
        super.sendEvent(event)
    }

    /// Arrows nudge the selected layer (⇧ for 10 points), Esc deselects, ⌫ / ⌦ delete it.
    private func handlePlainKey(_ event: NSEvent, editor: ScreenshotEditorViewModel) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1

        switch Int(event.keyCode) {
        case 51, 117: // ⌫, ⌦
            guard editor.canDeleteSelection else { return false }
            editor.removeSelectedItem()
        case 53: // Esc
            guard editor.selectedItemID != nil else { return false }
            editor.selectedItemID = nil
        case 123: return editor.nudgeSelection(dx: -step, dy: 0)
        case 124: return editor.nudgeSelection(dx: step, dy: 0)
        case 125: return editor.nudgeSelection(dx: 0, dy: step)
        case 126: return editor.nudgeSelection(dx: 0, dy: -step)
        default: return false
        }
        return true
    }

    // MARK: Menu Actions

    @objc func saveDocument(_ sender: Any?) { editor?.save() }
    @objc func copy(_ sender: Any?) { editor?.copyToClipboard() }
    @objc func paste(_ sender: Any?) { editor?.pasteImage() }
    @objc func delete(_ sender: Any?) { editor?.removeSelectedItem() }
    @objc func undo(_ sender: Any?) { editor?.undo() }
    @objc func redo(_ sender: Any?) { editor?.redo() }
    @objc func zoomIn(_ sender: Any?) { editor?.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { editor?.zoomOut() }
    @objc func zoomToActualSize(_ sender: Any?) { editor?.zoomToActualSize() }
    @objc func zoomToFit(_ sender: Any?) { editor?.zoomToFit() }
    @objc func toggleInspector(_ sender: Any?) { editor?.toggleInspector() }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let editor, let action = menuItem.action else { return super.validateMenuItem(menuItem) }
        switch action {
        case #selector(saveDocument(_:)), #selector(copy(_:)):
            return editor.canExport
        case #selector(paste(_:)):
            return editor.canPasteImage
        case #selector(delete(_:)):
            return editor.canDeleteSelection
        case #selector(undo(_:)):
            return editor.canUndo
        case #selector(redo(_:)):
            return editor.canRedo
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(zoomToActualSize(_:)), #selector(zoomToFit(_:)):
            return true
        case #selector(toggleInspector(_:)):
            menuItem.title = editor.isInspectorPresented
                ? String(localized: "Hide Inspector")
                : String(localized: "Show Inspector")
            return true
        default:
            return super.validateMenuItem(menuItem)
        }
    }
}
