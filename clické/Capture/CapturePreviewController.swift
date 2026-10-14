import AppKit
import os

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clicke", category: "Preview")

// MARK: - Capture Preview Controller

/// Shows floating capture previews in the bottom-right corner of the screen under the pointer,
/// like the macOS screenshot thumbnail. Successive captures stack upward (newest at the bottom).
final class CapturePreviewController {
    static let shared = CapturePreviewController()

    private static let maximumPerScreen = 3
    private static let margin: CGFloat = 16
    private static let spacing: CGFloat = 12

    /// Visible previews, oldest first.
    private var previews: [CapturePreview] = []

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Shows a preview for `capture`.
    func show(_ capture: ScreenCapture) {
        let screen = ScreenLocator.screenUnderPointer()
        let displayID = screen.flatMap { ScreenLocator.displayID(of: $0) } ?? CGMainDisplayID()
        let preview = CapturePreview(capture: capture, displayID: displayID, controller: self)
        previews.append(preview)

        trimStack(displayID: displayID)
        layout(displayID: displayID, appearing: preview)

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: String(localized: "Screenshot taken. A preview is in the bottom-right corner of the screen."),
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    /// Removes `preview` and closes the gap it leaves.
    func dismiss(_ preview: CapturePreview) {
        guard let index = previews.firstIndex(where: { $0 === preview }) else { return }
        previews.remove(at: index)
        preview.animateOut()
        layout(displayID: preview.displayID, appearing: nil)
    }

    /// A preview finished a drag or closed its Save panel: the stack can be trimmed again.
    func previewDidBecomeIdle(_ preview: CapturePreview) {
        trimStack(displayID: preview.displayID)
    }

    /// Keeps the stack short: the oldest previews on the screen make room, except the ones in use
    /// (being dragged, or with a Save panel open). Those are trimmed once they're idle again.
    private func trimStack(displayID: CGDirectDisplayID) {
        let sameScreen = previews.filter { $0.displayID == displayID }
        var excess = sameScreen.count - Self.maximumPerScreen
        guard excess > 0 else { return }

        let removable = sameScreen.filter { !$0.isBusy }.prefix(excess)
        for old in removable {
            dismiss(old)
            excess -= 1
        }
    }

    // MARK: Layout

    private func layout(displayID: CGDirectDisplayID, appearing: CapturePreview?) {
        guard let screen = ScreenLocator.screen(withDisplayID: displayID) ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        var y = visibleFrame.minY + Self.margin

        for preview in previews.reversed() where preview.displayID == displayID {
            let size = preview.size
            let frame = NSRect(
                x: visibleFrame.maxX - Self.margin - size.width,
                y: y,
                width: size.width,
                height: size.height
            )
            y += size.height + Self.spacing

            if preview === appearing {
                preview.animateIn(to: frame)
            } else {
                preview.move(to: frame)
            }
        }
    }

    @objc private func screenParametersDidChange() {
        // A display was disconnected or rearranged: move previews of missing displays to the main screen.
        let mainID = NSScreen.main.flatMap { ScreenLocator.displayID(of: $0) } ?? CGMainDisplayID()
        for preview in previews where ScreenLocator.screen(withDisplayID: preview.displayID) == nil {
            preview.displayID = mainID
        }
        for displayID in Set(previews.map(\.displayID)) {
            layout(displayID: displayID, appearing: nil)
        }
    }
}

// MARK: - Capture Preview

/// One preview panel: owns its window, auto-dismiss timer, quick actions and context menu.
final class CapturePreview: NSObject, CapturePreviewViewDelegate, NSMenuDelegate {
    private static let displayDuration: Duration = .seconds(6)
    private static let minimumRemainingDuration: Duration = .seconds(2)

    let capture: ScreenCapture
    var displayID: CGDirectDisplayID
    private weak var controller: CapturePreviewController?
    private let panel: CapturePreviewPanel
    private let previewView: CapturePreviewView

    private var dismissTask: Task<Void, Never>?
    private var remainingDuration = CapturePreview.displayDuration
    private var timerStart: ContinuousClock.Instant?
    private var isHovered = false
    private var isDismissed = false

    /// Operations that need the preview to stay (drag, Save panel, context menu).
    private var busyCount = 0

    /// Dragging, saving or showing its menu: the preview must stay until the operation ends.
    var isBusy: Bool { busyCount > 0 }

    var size: NSSize { panel.frame.size }

    init(capture: ScreenCapture, displayID: CGDirectDisplayID, controller: CapturePreviewController) {
        self.capture = capture
        self.displayID = displayID
        self.controller = controller
        previewView = CapturePreviewView(capture: capture)
        panel = CapturePreviewPanel(contentRect: previewView.frame)
        super.init()
        previewView.delegate = self
        panel.contentView = previewView
    }

    // MARK: Animation

    func animateIn(to frame: NSRect) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: frame.width + 24, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.2 : 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            // AppKit calls completion handlers on the main thread.
            MainActor.assumeIsolated {
                self?.previewView.refreshHoverState()
            }
        }
        startTimer()
    }

    func move(to frame: NSRect) {
        guard panel.frame != frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func animateOut() {
        guard !isDismissed else { return }
        isDismissed = true
        dismissTask?.cancel()
        dismissTask = nil

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if !reduceMotion {
                panel.animator().setFrame(panel.frame.offsetBy(dx: panel.frame.width + 24, dy: 0), display: true)
            }
            panel.animator().alphaValue = 0
        } completionHandler: {
            // AppKit calls completion handlers on the main thread.
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.contentView = nil
                panel.close()
            }
        }
    }

    private func dismiss() {
        controller?.dismiss(self)
    }

    // MARK: Busy State

    private func beginBusy() {
        busyCount += 1
        pauseTimer()
    }

    /// - Parameter dismissing: The operation completed the preview's job (it's closed right away).
    private func endBusy(dismissing: Bool) {
        guard busyCount > 0 else { return }
        busyCount -= 1
        guard !isBusy, !isDismissed else { return }
        if dismissing {
            dismiss()
        } else {
            startTimer()
            controller?.previewDidBecomeIdle(self)
        }
    }

    // MARK: Auto-dismiss

    /// Counts down the remaining display time, unless hovered or busy.
    private func startTimer() {
        guard !isDismissed, !isHovered, !isBusy, dismissTask == nil else { return }
        timerStart = .now
        let duration = remainingDuration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Stops the countdown and keeps the time left for later.
    private func pauseTimer() {
        guard let dismissTask else { return }
        dismissTask.cancel()
        self.dismissTask = nil
        if let timerStart {
            remainingDuration = max(remainingDuration - (ContinuousClock.now - timerStart), Self.minimumRemainingDuration)
        }
        timerStart = nil
    }

    // MARK: Actions

    private func edit() {
        dismiss()
        guard let image = capture.makeImage() else {
            ToastManager.shared.show(
                message: String(localized: "Couldn’t Open the Screenshot"),
                icon: "exclamationmark.triangle.fill",
                success: false
            )
            return
        }
        ScreenshotEditorWindow.shared.show(with: image)
    }

    private func copyToClipboard() {
        dismiss()
        if CaptureExporter.copyToPasteboard(capture) {
            ToastManager.shared.show(message: String(localized: "Copied to Clipboard"), icon: "doc.on.clipboard.fill", success: true)
        } else {
            ToastManager.shared.show(
                message: String(localized: "Couldn’t Copy the Screenshot"),
                icon: "exclamationmark.triangle.fill",
                success: false
            )
        }
    }

    private func presentSavePanel() {
        beginBusy()
        // Let the Save panel cover the preview.
        panel.level = .normal
        CaptureExporter.presentSavePanel(for: capture) { [weak self] saved in
            guard let self else { return }
            panel.level = .floating
            endBusy(dismissing: saved)
        }
    }

    private func saveToDefaultFolder() {
        beginBusy()
        let capture = capture
        Task { [weak self] in
            let saved = await CaptureExporter.saveToDefaultFolder(capture)
            self?.endBusy(dismissing: saved)
        }
    }

    // MARK: CapturePreviewViewDelegate

    func previewViewDidRequestEdit(_ view: CapturePreviewView) {
        edit()
    }

    func previewViewDidRequestCopy(_ view: CapturePreviewView) {
        copyToClipboard()
    }

    func previewViewDidRequestSave(_ view: CapturePreviewView) {
        presentSavePanel()
    }

    func previewViewDidRequestClose(_ view: CapturePreviewView) {
        dismiss()
    }

    func previewView(_ view: CapturePreviewView, hoverDidChange isHovered: Bool) {
        self.isHovered = isHovered
        if isHovered {
            pauseTimer()
        } else {
            startTimer()
        }
    }

    func previewViewFileForDragging(_ view: CapturePreviewView) -> URL? {
        do {
            return try CaptureTemporaryStorage.writeDragFile(capture.pngData, named: capture.fileName)
        } catch {
            logger.error("Couldn't write the file to drag: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    func previewViewDidBeginDragging(_ view: CapturePreviewView) {
        beginBusy()
    }

    func previewView(_ view: CapturePreviewView, draggingDidEndWith operation: NSDragOperation) {
        // Dropped somewhere: the preview has done its job (same as the macOS thumbnail).
        endBusy(dismissing: !operation.isEmpty)
    }

    func previewViewContextMenu(_ view: CapturePreviewView) -> NSMenu? {
        guard !isDismissed else { return nil }
        let folderName = CaptureExporter.displayName(of: AppSettings.current.saveDirectoryURL)

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeMenuItem(String(localized: "Edit"), action: #selector(editFromMenu(_:))))
        menu.addItem(makeMenuItem(String(localized: "Copy"), action: #selector(copyFromMenu(_:))))
        menu.addItem(makeMenuItem(String(localized: "Save…"), action: #selector(saveFromMenu(_:))))
        menu.addItem(makeMenuItem(
            String(localized: "Save to “\(folderName)”", comment: "Preview menu: save to the folder chosen in Settings"),
            action: #selector(saveToFolderFromMenu(_:))
        ))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(String(localized: "Close"), action: #selector(closeFromMenu(_:))))
        return menu
    }

    private func makeMenuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: Context Menu

    // The menu's action runs after `menuDidClose(_:)`, so the preview stays put while it's open.

    func menuWillOpen(_ menu: NSMenu) {
        beginBusy()
    }

    func menuDidClose(_ menu: NSMenu) {
        endBusy(dismissing: false)
    }

    @objc private func editFromMenu(_ sender: NSMenuItem) {
        edit()
    }

    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        copyToClipboard()
    }

    @objc private func saveFromMenu(_ sender: NSMenuItem) {
        presentSavePanel()
    }

    @objc private func saveToFolderFromMenu(_ sender: NSMenuItem) {
        saveToDefaultFolder()
    }

    @objc private func closeFromMenu(_ sender: NSMenuItem) {
        dismiss()
    }
}

// MARK: - Capture Preview Panel

/// A borderless floating panel that never activates Clické nor takes keyboard focus.
final class CapturePreviewPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Keep the preview out of later captures.
        sharingType = .none
        setAccessibilityLabel(String(localized: "Screenshot preview"))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
