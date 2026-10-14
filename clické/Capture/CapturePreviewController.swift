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

        // Keep the stack short: the oldest previews on this screen make room.
        let sameScreen = previews.filter { $0.displayID == displayID }
        for old in sameScreen.dropLast(Self.maximumPerScreen) {
            dismiss(old)
        }

        layout(displayID: displayID, appearing: preview)

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: String(localized: "Capture ready. Preview in the bottom-right corner of the screen."),
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

/// One preview panel: owns its window, auto-dismiss timer and quick actions.
final class CapturePreview: NSObject, CapturePreviewViewDelegate {
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
    /// Dragging or saving: the preview must stay until the operation ends.
    private var isBusy = false
    private var isDismissed = false

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
            self?.previewView.refreshHoverState()
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
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
    }

    private func dismiss() {
        controller?.dismiss(self)
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

    // MARK: CapturePreviewViewDelegate

    func previewViewDidRequestEdit(_ view: CapturePreviewView) {
        dismiss()
        ScreenshotEditorWindow.shared.show(with: capture.image)
    }

    func previewViewDidRequestCopy(_ view: CapturePreviewView) {
        dismiss()
        let capture = capture
        Task {
            await CaptureExporter.copyToPasteboard(capture)
            ToastManager.shared.show(message: String(localized: "Copied to Clipboard"), icon: "doc.on.clipboard.fill", success: true)
        }
    }

    func previewViewDidRequestSave(_ view: CapturePreviewView) {
        isBusy = true
        pauseTimer()
        // Let the Save panel cover the preview.
        panel.level = .normal
        CaptureExporter.presentSavePanel(for: capture) { [weak self] saved in
            guard let self else { return }
            isBusy = false
            panel.level = .floating
            if saved {
                dismiss()
            } else {
                startTimer()
            }
        }
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
        isBusy = true
        pauseTimer()
    }

    func previewView(_ view: CapturePreviewView, draggingDidEndWith operation: NSDragOperation) {
        isBusy = false
        if operation.isEmpty {
            startTimer()
        } else {
            // Dropped somewhere: the preview has done its job (same as the macOS thumbnail).
            dismiss()
        }
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
        setAccessibilityLabel(String(localized: "Capture Preview"))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
