import AppKit

// MARK: - Delegate

/// Receives the user's interactions with a capture preview.
protocol CapturePreviewViewDelegate: AnyObject {
    func previewViewDidRequestEdit(_ view: CapturePreviewView)
    func previewViewDidRequestCopy(_ view: CapturePreviewView)
    func previewViewDidRequestSave(_ view: CapturePreviewView)
    func previewViewDidRequestClose(_ view: CapturePreviewView)
    func previewView(_ view: CapturePreviewView, hoverDidChange isHovered: Bool)
    /// The PNG file handed to the drop target (written on demand when a drag starts).
    func previewViewFileForDragging(_ view: CapturePreviewView) -> URL?
    func previewViewDidBeginDragging(_ view: CapturePreviewView)
    func previewView(_ view: CapturePreviewView, draggingDidEndWith operation: NSDragOperation)
}

// MARK: - Capture Preview View

/// A Liquid Glass card showing a capture thumbnail. Hovering reveals quick actions (Edit, Copy,
/// Save…, Close); clicking the thumbnail opens the editor, dragging it drops a PNG file.
final class CapturePreviewView: NSView {
    private enum Metrics {
        static let maxImageSize = CGSize(width: 224, height: 150)
        static let minCardSize = CGSize(width: 184, height: 136)
        static let padding: CGFloat = 8
        static let cornerRadius: CGFloat = 18
        static let controlInset: CGFloat = 8
    }

    weak var delegate: CapturePreviewViewDelegate?

    private let thumbnailView: CaptureThumbnailView
    private let closeButton: NSButton
    private let actionStack: NSStackView
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false

    /// The card size for a capture of `pointSize`.
    static func cardSize(for pointSize: CGSize) -> CGSize {
        let image = imageSize(for: pointSize)
        return CGSize(
            width: max(Metrics.minCardSize.width, image.width + 2 * Metrics.padding),
            height: max(Metrics.minCardSize.height, image.height + 2 * Metrics.padding)
        )
    }

    /// The thumbnail size: fits `maxImageSize`, never upscaled.
    private static func imageSize(for pointSize: CGSize) -> CGSize {
        guard pointSize.width > 0, pointSize.height > 0 else { return Metrics.maxImageSize }
        let scale = min(1, Metrics.maxImageSize.width / pointSize.width, Metrics.maxImageSize.height / pointSize.height)
        return CGSize(
            width: max(1, (pointSize.width * scale).rounded()),
            height: max(1, (pointSize.height * scale).rounded())
        )
    }

    init(capture: ScreenCapture) {
        let cardSize = Self.cardSize(for: capture.image.size)
        thumbnailView = CaptureThumbnailView(
            image: capture.thumbnail,
            imageSize: Self.imageSize(for: capture.image.size),
            pngData: capture.pngData
        )
        closeButton = PreviewButton()
        actionStack = PassthroughStackView()
        super.init(frame: NSRect(origin: .zero, size: cardSize))

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Capture Preview"))

        buildHierarchy()
        setControlsVisible(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Layout

    private func buildHierarchy() {
        let glass = NSGlassEffectView(frame: bounds)
        glass.cornerRadius = Metrics.cornerRadius
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)

        let content = NSView(frame: glass.bounds)
        content.autoresizingMask = [.width, .height]
        glass.contentView = content

        thumbnailView.frame = content.bounds
        thumbnailView.autoresizingMask = [.width, .height]
        thumbnailView.onClick = { [weak self] in
            guard let self else { return }
            delegate?.previewViewDidRequestEdit(self)
        }
        thumbnailView.fileForDragging = { [weak self] in
            guard let self else { return nil }
            return delegate?.previewViewFileForDragging(self)
        }
        thumbnailView.onDragBegan = { [weak self] in
            guard let self else { return }
            delegate?.previewViewDidBeginDragging(self)
        }
        thumbnailView.onDragEnded = { [weak self] operation in
            guard let self else { return }
            delegate?.previewView(self, draggingDidEndWith: operation)
        }
        content.addSubview(thumbnailView)

        // Close (top-left, like notifications)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Close"))
        closeButton.imagePosition = .imageOnly
        closeButton.bezelStyle = .glass
        closeButton.borderShape = .circle
        closeButton.controlSize = .small
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = String(localized: "Close")
        closeButton.setAccessibilityLabel(String(localized: "Close"))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(closeButton)

        // Quick actions (centered, equal widths)
        actionStack.orientation = .vertical
        actionStack.alignment = .centerX
        actionStack.spacing = 6
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        let actionButtons = [
            makeActionButton(title: String(localized: "Edit"), symbol: "pencil", action: #selector(editClicked)),
            makeActionButton(title: String(localized: "Copy"), symbol: "doc.on.doc", action: #selector(copyClicked)),
            makeActionButton(title: String(localized: "Save…"), symbol: "square.and.arrow.down", action: #selector(saveClicked))
        ]
        for button in actionButtons {
            actionStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: actionStack.widthAnchor).isActive = true
        }
        content.addSubview(actionStack)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Metrics.controlInset),
            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: Metrics.controlInset),
            actionStack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            actionStack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
    }

    private func makeActionButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = PreviewButton()
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.target = self
        button.action = action
        return button
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        // `.activeAlways`: the panel never makes Clické active, hover must still work.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    /// Syncs the hover state with the pointer (e.g. when the panel appears under it).
    func refreshHoverState() {
        guard let window else { return }
        setHovered(NSMouseInRect(NSEvent.mouseLocation, window.frame, false))
    }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        setControlsVisible(hovered, animated: true)
        delegate?.previewView(self, hoverDidChange: hovered)
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool) {
        let alpha: CGFloat = visible ? 1 : 0
        thumbnailView.setDimmed(visible)
        guard animated else {
            closeButton.alphaValue = alpha
            actionStack.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            closeButton.animator().alphaValue = alpha
            actionStack.animator().alphaValue = alpha
        }
    }

    // MARK: Actions

    @objc private func editClicked() {
        delegate?.previewViewDidRequestEdit(self)
    }

    @objc private func copyClicked() {
        delegate?.previewViewDidRequestCopy(self)
    }

    @objc private func saveClicked() {
        delegate?.previewViewDidRequestSave(self)
    }

    @objc private func closeClicked() {
        delegate?.previewViewDidRequestClose(self)
    }
}

// MARK: - Thumbnail View

/// Draws the capture thumbnail and acts as a dragging source: a click opens the editor,
/// a drag hands a PNG file to Finder, Mail, Slack, browsers, etc.
private final class CaptureThumbnailView: NSView, NSDraggingSource {
    var onClick: (() -> Void)?
    var fileForDragging: (() -> URL?)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((NSDragOperation) -> Void)?

    private let image: CGImage
    private let imageSize: CGSize
    private let pngData: Data
    private let imageLayer = CALayer()
    private let scrimLayer = CALayer()
    private var mouseDownEvent: NSEvent?

    /// Minimum pointer travel before a press becomes a drag.
    private static let dragThreshold: CGFloat = 4

    init(image: CGImage, imageSize: CGSize, pngData: Data) {
        self.image = image
        self.imageSize = imageSize
        self.pngData = pngData
        super.init(frame: .zero)
        wantsLayer = true

        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.cornerRadius = 10
        imageLayer.cornerCurve = .continuous
        imageLayer.masksToBounds = true
        imageLayer.borderWidth = 0.5

        scrimLayer.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        scrimLayer.opacity = 0
        imageLayer.addSublayer(scrimLayer)

        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "Capture"))
        setAccessibilityHelp(String(localized: "Click to edit the capture, or drag it into another app."))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.addSublayer(imageLayer)
        return layer
    }

    override func updateLayer() {
        // Hairline so white captures stay visible on light glass (resolved for the current appearance).
        effectiveAppearance.performAsCurrentDrawingAppearance {
            imageLayer.borderColor = NSColor.separatorColor.cgColor
        }
    }

    override func layout() {
        super.layout()
        let rect = imageRect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = rect
        scrimLayer.frame = CGRect(origin: .zero, size: rect.size)
        CATransaction.commit()
    }

    /// The thumbnail's frame, centered in the view.
    private var imageRect: CGRect {
        CGRect(
            x: ((bounds.width - imageSize.width) / 2).rounded(),
            y: ((bounds.height - imageSize.height) / 2).rounded(),
            width: imageSize.width,
            height: imageSize.height
        )
    }

    /// Dims the thumbnail so the quick actions stay legible.
    func setDimmed(_ dimmed: Bool) {
        scrimLayer.opacity = dimmed ? 1 : 0   // implicit layer animation
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        let distance = hypot(
            event.locationInWindow.x - start.locationInWindow.x,
            event.locationInWindow.y - start.locationInWindow.y
        )
        guard distance >= Self.dragThreshold else { return }
        mouseDownEvent = nil
        beginDragging(with: start)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        if mouseDownEvent != nil {
            onClick?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    // MARK: Dragging

    private func beginDragging(with event: NSEvent) {
        guard let fileURL = fileForDragging?() else {
            NSSound.beep()
            return
        }

        let item = NSDraggingItem(pasteboardWriter: CaptureDragWriter(fileURL: fileURL, pngData: pngData))
        item.setDraggingFrame(imageRect, contents: NSImage(cgImage: image, size: imageRect.size))

        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
        onDragBegan?()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?(operation)
    }
}

// MARK: - Drag Pasteboard Writer

/// Offers the dragged capture as a file URL first (Finder, Mail, Slack, browsers…) and as PNG
/// data for apps that only accept image data. The PNG is only provided if a target asks for it.
private final class CaptureDragWriter: NSObject, NSPasteboardWriting {
    private let fileURL: NSURL
    private let pngData: Data

    init(fileURL: URL, pngData: Data) {
        self.fileURL = fileURL as NSURL
        self.pngData = pngData
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        fileURL.writableTypes(for: pasteboard) + [.png]
    }

    func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .png ? .promised : []
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .png ? pngData : fileURL.pasteboardPropertyList(forType: type)
    }
}

// MARK: - Controls

/// A button that reacts to the first click even though the preview panel never becomes key.
private final class PreviewButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A stack view that lets clicks between its buttons fall through to the thumbnail.
private final class PassthroughStackView: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self ? nil : view
    }
}
