import SwiftUI
import AppKit
import Observation
import os
import UniformTypeIdentifiers

/// A request to present the redaction sheet for one layer.
struct RedactionRequest: Identifiable {
    let id = UUID()
    let itemID: UUID
    let image: NSImage
}

/// Keyboard commands handled by the editor window (they work without a menu bar).
enum EditorCommand {
    case copy, save, close, undo, redo
    case zoomIn, zoomOut, zoomToFit, actualSize
    case deleteSelection, deselect, toggleInspector, addImage
    case nudge(dx: CGFloat, dy: CGFloat)
}

// MARK: - ScreenshotEditorViewModel

/// State and actions of the screenshot editor.
///
/// The *document* (`config` + `items`) is the single source of truth for both the canvas and the
/// export; every change to it is recorded for undo. Zoom, pan and selection are view state.
@Observable
final class ScreenshotEditorViewModel {

    // MARK: Document

    /// Canvas style (background, effects, size).
    var config: ScreenshotStyleConfig {
        didSet {
            guard config != oldValue else { return }
            documentDidChange(from: EditorSnapshot(config: oldValue, items: items))
        }
    }

    /// The layers, in insertion order (`zIndex` gives the stacking order).
    var items: [CanvasItem] {
        didSet {
            guard items != oldValue else { return }
            documentDidChange(from: EditorSnapshot(config: config, items: oldValue))
        }
    }

    var selectedItemID: UUID?

    /// Canvas layout derived from the document.
    var geometry: CanvasGeometry { CanvasGeometry(config: config, items: items) }

    // MARK: View State

    /// Screen points per canvas point.
    private(set) var zoom: CGFloat = 1
    /// Offset of the canvas center from the viewport center, in screen points.
    var pan: CGSize = .zero
    /// While `true`, the canvas re-fits whenever the window or the canvas size changes.
    private(set) var isFitMode = true
    private(set) var viewportSize: CGSize = .zero

    var isInspectorPresented = true
    var inspectorTab: InspectorTab {
        didSet { EditorPreferences.inspectorTab = inspectorTab }
    }

    var redactionRequest: RedactionRequest?
    private(set) var isExporting = false

    static let zoomRange: ClosedRange<CGFloat> = 0.05...8

    // MARK: Export Settings

    var exportFormat: ExportFormat {
        didSet { EditorPreferences.exportFormat = exportFormat }
    }

    /// JPEG quality, 0–1.
    var jpegQuality: Double {
        didSet { EditorPreferences.jpegQuality = jpegQuality }
    }

    // MARK: Images

    /// The background image at the resolution the canvas currently needs.
    private(set) var backgroundPreview: CGImage?
    private var backgroundPreviewKey: String?
    private var backgroundPreviewSource: BackgroundImageSource?
    private var backgroundTask: Task<Void, Never>?

    /// Small rendering of the result, shown in the inspector footer and dragged out.
    private(set) var exportThumbnail: CGImage?
    private var thumbnailTask: Task<Void, Never>?

    let wallpapers = WallpaperLibrary.shared

    /// The window hosting the editor (save panels and alerts are attached to it).
    weak var window: NSWindow?

    // MARK: History

    private var history = EditorHistory()
    private var isRestoringSnapshot = false
    private var interactionDepth = 0
    private var commitTask: Task<Void, Never>?
    /// Incremented on every document change.
    private(set) var documentVersion = 0

    /// Style given to new layers: the last style edited, remembered across captures.
    private var layerStyleTemplate: LayerStyle

    // MARK: Drag Export

    private var dragExport: (version: Int, format: ExportFormat, url: URL)?
    private var dragExportTask: Task<Void, Never>?

    // MARK: - Initialization

    init(images: [NSImage]) {
        let saved = EditorPreferences.loadStyle()
        var config = saved?.canvas ?? .default
        // A previously imported background may have been moved or deleted.
        if config.backgroundImage.url == nil {
            config.backgroundImage = .defaultWallpaper
        }
        self.config = config
        self.layerStyleTemplate = saved?.layer ?? .default
        self.items = []
        self.exportFormat = EditorPreferences.exportFormat
        self.jpegQuality = EditorPreferences.jpegQuality
        self.inspectorTab = EditorPreferences.inspectorTab

        if case .file(let url) = config.backgroundImage {
            wallpapers.addImportedImage(at: url)
        }

        isRestoringSnapshot = true // the initial layers aren't an undoable change
        images.forEach { addImage($0) }
        isRestoringSnapshot = false
        updateBackgroundPreview()
        scheduleThumbnailRefresh()
    }

    // MARK: - Document Changes

    private var snapshot: EditorSnapshot { EditorSnapshot(config: config, items: items) }

    private func documentDidChange(from previous: EditorSnapshot) {
        documentVersion &+= 1
        guard !isRestoringSnapshot else { return }

        history.willChange(from: previous)
        scheduleCommit()

        if let selected = selectedItem, selected.style != layerStyleTemplate {
            layerStyleTemplate = selected.style
        }
        if CanvasGeometry(config: previous.config, items: previous.items).canvasSize != geometry.canvasSize {
            refitIfNeeded()
        }
        updateBackgroundPreview()
        scheduleThumbnailRefresh()
    }

    /// Marks the start of a continuous edit (slider or canvas drag): it becomes a single undo step.
    func beginInteraction() {
        interactionDepth += 1
        commitTask?.cancel()
    }

    func endInteraction() {
        interactionDepth = max(interactionDepth - 1, 0)
        if interactionDepth == 0 {
            commitHistory()
        }
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        guard interactionDepth == 0 else { return }
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.commitHistory()
        }
    }

    private func commitHistory() {
        commitTask?.cancel()
        if history.commit(current: snapshot) {
            persistStyle()
        }
    }

    // MARK: Undo / Redo

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    func undo() {
        interactionDepth = 0
        commitTask?.cancel()
        guard let previous = history.undo(current: snapshot) else {
            NSSound.beep()
            return
        }
        restore(previous)
    }

    func redo() {
        interactionDepth = 0
        commitTask?.cancel()
        guard let next = history.redo(current: snapshot) else {
            NSSound.beep()
            return
        }
        restore(next)
    }

    private func restore(_ snapshot: EditorSnapshot) {
        let previousCanvas = geometry.canvasSize
        isRestoringSnapshot = true
        config = snapshot.config
        items = snapshot.items
        isRestoringSnapshot = false

        if let id = selectedItemID, !items.contains(where: { $0.id == id }) {
            selectedItemID = items.max { $0.zIndex < $1.zIndex }?.id
        }
        if let selected = selectedItem {
            layerStyleTemplate = selected.style
        }
        if previousCanvas != geometry.canvasSize {
            refitIfNeeded()
        }
        persistStyle()
        updateBackgroundPreview()
        scheduleThumbnailRefresh()
    }

    // MARK: Style Persistence

    private func persistStyle() {
        EditorPreferences.saveStyle(.init(canvas: config, layer: layerStyleTemplate))
    }

    /// Restores the default look (background, effects, canvas, and every layer's frame, corners and shadow).
    func resetStyle() {
        config = .default
        layerStyleTemplate = .default
        for index in items.indices {
            items[index].style = .default
        }
        commitHistory()
    }

    /// Called when the window closes.
    func editorWillClose() {
        commitHistory()
        persistStyle()
        backgroundTask?.cancel()
        thumbnailTask?.cancel()
        dragExportTask?.cancel()
    }

    // MARK: - Layers

    var selectedItem: CanvasItem? {
        guard let id = selectedItemID else { return nil }
        return items.first { $0.id == id }
    }

    private func index(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    /// A binding to a layer that stays valid if the layer is removed (writes are then ignored).
    func binding(forItem id: UUID) -> Binding<CanvasItem>? {
        guard let current = items.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.items.first { $0.id == id } ?? current },
            set: { [weak self] newValue in
                guard let self, let index = self.index(of: id) else { return }
                self.items[index] = newValue
            }
        )
    }

    /// Adds an image as a new layer (selected, slightly offset from the previous ones).
    func addImage(_ image: NSImage) {
        guard let layer = LayerImage(nsImage: image) else {
            Logger.editor.error("Ignored an image without bitmap data.")
            return
        }
        var item = CanvasItem(image: layer, style: layerStyleTemplate)
        let cascade = CGFloat(items.count) * 30
        item.offset = CGSize(width: cascade, height: cascade)
        item.zIndex = (items.map(\.zIndex).max() ?? -1) + 1
        items.append(item)
        selectedItemID = item.id
    }

    /// Shows an open panel and adds the chosen images.
    func addImagesFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = String(localized: "Choose images to add to the canvas.")
        panel.prompt = String(localized: "Add")
        present(panel) { [weak self] urls in
            for url in urls {
                if let image = NSImage(contentsOf: url) {
                    self?.addImage(image)
                }
            }
        }
    }

    /// Adds dropped files or images as layers.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor [weak self] in
                        if let image = NSImage(contentsOf: url), image.isValid {
                            self?.addImage(image)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor [weak self] in
                        if let image = NSImage(data: data) {
                            self?.addImage(image)
                        }
                    }
                }
            }
        }
        return accepted
    }

    func removeSelectedItem() {
        guard items.count > 1, let id = selectedItemID else { return }
        items.removeAll { $0.id == id }
        selectedItemID = items.max { $0.zIndex < $1.zIndex }?.id
    }

    func bringSelectedToFront() {
        guard let id = selectedItemID, let index = index(of: id) else { return }
        items[index].zIndex = (items.map(\.zIndex).max() ?? 0) + 1
    }

    func sendSelectedToBack() {
        guard let id = selectedItemID, let index = index(of: id) else { return }
        items[index].zIndex = (items.map(\.zIndex).min() ?? 0) - 1
    }

    func setOffset(_ offset: CGSize, forItem id: UUID) {
        guard let index = index(of: id) else { return }
        items[index].offset = offset
    }

    func setScale(_ scale: Double, forItem id: UUID) {
        guard let index = index(of: id) else { return }
        items[index].scale = min(max(scale, 5), 400)
    }

    /// Moves the selected layer by a few canvas points (arrow keys).
    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard let id = selectedItemID, let index = index(of: id) else { return }
        items[index].offset.width += dx
        items[index].offset.height += dy
    }

    /// Centers the layers on the canvas (as a group, keeping their arrangement).
    func centerLayers() {
        guard !items.isEmpty else { return }
        let geometry = self.geometry
        let union = items
            .map { item -> CGRect in
                let size = geometry.layerSize(for: item)
                return CGRect(x: item.offset.width - size.width / 2, y: item.offset.height - size.height / 2, width: size.width, height: size.height)
            }
            .reduce(CGRect.null) { $0.union($1) }
        let shift = CGSize(width: union.midX, height: union.midY)
        for index in items.indices {
            items[index].offset.width -= shift.width
            items[index].offset.height -= shift.height
        }
    }

    /// Copies the selected layer's style to every layer.
    func applySelectedStyleToAllLayers() {
        guard let style = selectedItem?.style else { return }
        for index in items.indices {
            items[index].style = style
        }
    }

    // MARK: - Redaction

    func redactSelectedLayer() {
        guard let item = selectedItem ?? items.max(by: { $0.zIndex < $1.zIndex }) else { return }
        selectedItemID = item.id
        redactionRequest = RedactionRequest(itemID: item.id, image: item.image.nsImage)
    }

    func applyRedaction(_ image: NSImage, toItem id: UUID) {
        redactionRequest = nil
        guard let layer = LayerImage(nsImage: image), let index = index(of: id) else { return }
        items[index].image = layer
        commitHistory()
    }

    // MARK: - Background

    func selectBackgroundColor(_ color: RGBAColor) {
        config.backgroundColor = color
        config.backgroundType = .color
    }

    func selectGradient(_ fill: GradientFill) {
        config.gradient = fill
        config.backgroundType = .gradient
    }

    func selectWallpaper(_ source: BackgroundImageSource) {
        config.backgroundImage = source
        config.backgroundType = .image
    }

    func randomizeGradient() {
        let baseHue = Double.random(in: 0...1)
        func color(hueShift: ClosedRange<Double>, saturation: ClosedRange<Double>, brightness: ClosedRange<Double>) -> RGBAColor {
            let hue = (baseHue + Double.random(in: hueShift)).truncatingRemainder(dividingBy: 1)
            return RGBAColor(NSColor(
                hue: hue,
                saturation: Double.random(in: saturation),
                brightness: Double.random(in: brightness),
                alpha: 1
            ))
        }
        var gradient = config.gradient
        gradient.colors = [
            color(hueShift: 0...0, saturation: 0.6...1, brightness: 0.7...0.95),
            color(hueShift: 0.08...0.2, saturation: 0.5...0.9, brightness: 0.6...0.9),
            color(hueShift: 0.25...0.5, saturation: 0.5...0.95, brightness: 0.65...0.95),
        ].prefix(gradient.colors.count).map { $0 }
        gradient.angle = Double(Int.random(in: 0...7) * 45)
        selectGradient(gradient)
    }

    /// Lets the user pick an image file as background.
    func importBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = String(localized: "Choose a background image.")
        present(panel) { [weak self] urls in
            guard let self, let url = urls.first else { return }
            selectWallpaper(wallpapers.addImportedImage(at: url))
        }
    }

    private func present(_ panel: NSOpenPanel, completion: @escaping ([URL]) -> Void) {
        if let window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK { completion(panel.urls) }
            }
        } else if panel.runModal() == .OK {
            completion(panel.urls)
        }
    }

    // MARK: Background Preview

    /// Decodes the background at the resolution the canvas displays (bucketed, cached, off the main actor).
    private func updateBackgroundPreview() {
        // Before the first layout the needed size is unknown; the grid thumbnail is shown meanwhile.
        guard config.backgroundType == .image, viewportSize != .zero, let url = config.backgroundImage.url else { return }

        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let canvas = geometry.canvasSize
        let displayScale = max(zoom, 0.1) * backing
        let longest = max(canvas.width, canvas.height) * displayScale
        // Power-of-two-ish steps so zooming doesn't re-decode at every tick.
        let bucket = [512, 1024, 1536, 2048, 3072, 4096, 6144, 8192].first { CGFloat($0) >= longest } ?? 8192
        let target = CGSize(
            width: canvas.width / max(canvas.width, canvas.height) * CGFloat(bucket),
            height: canvas.height / max(canvas.width, canvas.height) * CGFloat(bucket)
        )
        let aspect = (canvas.width / max(canvas.height, 1) * 20).rounded() / 20
        let key = "\(url.path)#\(bucket)#\(aspect)"
        guard key != backgroundPreviewKey else { return }
        backgroundPreviewKey = key

        // Switching wallpaper: show its grid thumbnail right away (if loaded), then the sharp version.
        if backgroundPreviewSource != config.backgroundImage {
            backgroundPreviewSource = config.backgroundImage
            backgroundPreview = wallpapers.thumbnails[config.backgroundImage]
        }

        backgroundTask?.cancel()
        backgroundTask = Task { [weak self] in
            let image = await ImageLoadingService.cachedImage(at: url, covering: target)
            guard !Task.isCancelled, let self, self.backgroundPreviewKey == key, let image else { return }
            self.backgroundPreview = image
            self.scheduleThumbnailRefresh()
        }
    }

    /// The background bitmap to draw right now (preview, or grid thumbnail while decoding).
    var canvasBackgroundImage: CGImage? {
        guard config.backgroundType == .image else { return nil }
        if backgroundPreviewSource == config.backgroundImage, let backgroundPreview {
            return backgroundPreview
        }
        return wallpapers.thumbnails[config.backgroundImage]
    }

    // MARK: - Zoom & Pan

    /// Called by the canvas when its size changes.
    func viewportDidChange(to size: CGSize) {
        guard size != viewportSize else { return }
        viewportSize = size
        refitIfNeeded()
    }

    /// Zoom that fits the whole canvas in the viewport (never above 100%).
    var fitZoom: CGFloat {
        let canvas = geometry.canvasSize
        let margin: CGFloat = 32
        guard viewportSize.width > margin * 2, viewportSize.height > margin * 2, canvas.width > 0, canvas.height > 0 else { return zoom }
        let fit = min((viewportSize.width - margin * 2) / canvas.width, (viewportSize.height - margin * 2) / canvas.height, 1)
        return min(max(fit, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    private func refitIfNeeded() {
        guard isFitMode else { return }
        zoom = fitZoom
        pan = .zero
        updateBackgroundPreview()
    }

    func zoomToFit() {
        withEditorAnimation {
            isFitMode = true
            zoom = fitZoom
            pan = .zero
        }
        updateBackgroundPreview()
    }

    func zoomToActualSize() {
        setZoom(1, anchor: nil, animated: true)
    }

    func zoomIn() {
        setZoom(steppedZoom(up: true), anchor: nil, animated: true)
    }

    func zoomOut() {
        setZoom(steppedZoom(up: false), anchor: nil, animated: true)
    }

    /// The next "nice" zoom level (25%, 33%, 50%, 67%, 100%, 150%…).
    private func steppedZoom(up: Bool) -> CGFloat {
        let levels: [CGFloat] = [0.05, 0.1, 0.125, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]
        if up {
            return levels.first { $0 > zoom * 1.01 } ?? Self.zoomRange.upperBound
        } else {
            return levels.last { $0 < zoom * 0.99 } ?? Self.zoomRange.lowerBound
        }
    }

    /// Sets the zoom, keeping the canvas point under `anchor` (viewport coordinates) in place.
    /// A `nil` anchor means the viewport center.
    func setZoom(_ newZoom: CGFloat, anchor: CGPoint?, animated: Bool = false) {
        let clamped = min(max(newZoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        guard clamped != zoom || isFitMode else { return }
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let point = anchor ?? center
        // Canvas-space position (relative to the canvas center) under the anchor.
        let canvasX = (point.x - center.x - pan.width) / zoom
        let canvasY = (point.y - center.y - pan.height) / zoom
        let newPan = CGSize(width: point.x - center.x - canvasX * clamped, height: point.y - center.y - canvasY * clamped)

        let apply = {
            self.isFitMode = false
            self.zoom = clamped
            self.pan = self.clampedPan(newPan, zoom: clamped)
        }
        if animated {
            withEditorAnimation(apply)
        } else {
            apply()
        }
        updateBackgroundPreview()
    }

    /// Pans the canvas by a delta in screen points.
    func panBy(_ delta: CGSize) {
        isFitMode = false
        pan = clampedPan(CGSize(width: pan.width + delta.width, height: pan.height + delta.height), zoom: zoom)
    }

    func setPan(_ newPan: CGSize) {
        isFitMode = false
        pan = clampedPan(newPan, zoom: zoom)
    }

    /// Keeps at least a part of the canvas on screen.
    private func clampedPan(_ pan: CGSize, zoom: CGFloat) -> CGSize {
        let canvas = geometry.canvasSize
        let visible: CGFloat = 80
        let maxX = max(canvas.width * zoom / 2 + viewportSize.width / 2 - visible, 0)
        let maxY = max(canvas.height * zoom / 2 + viewportSize.height / 2 - visible, 0)
        return CGSize(width: min(max(pan.width, -maxX), maxX), height: min(max(pan.height, -maxY), maxY))
    }

    /// Trackpad scrolling pans; ⌘ + scroll (or a mouse wheel with ⌘) zooms around the pointer.
    func handleScroll(_ event: NSEvent, at location: CGPoint) {
        let lineHeight: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        let dx = event.scrollingDeltaX * lineHeight
        let dy = event.scrollingDeltaY * lineHeight
        if event.modifierFlags.contains(.command) {
            let factor = exp(dy * 0.01) // ≈ 13% per mouse-wheel notch
            setZoom(zoom * factor, anchor: location)
        } else {
            panBy(CGSize(width: dx, height: dy))
        }
    }

    var zoomPercentage: Int { Int((zoom * 100).rounded()) }

    private func withEditorAnimation(_ changes: () -> Void) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            changes()
        } else {
            withAnimation(.snappy(duration: 0.25), changes)
        }
    }

    // MARK: - Export

    /// Copies the result to the clipboard (PNG + TIFF).
    func copyToClipboard() {
        guard !isExporting, !items.isEmpty else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            guard let output = await ScreenshotRenderer.render(config: config, items: items) else {
                presentError(message: String(localized: "The image couldn’t be rendered."))
                return
            }
            do {
                try await ScreenshotRenderer.copyToPasteboard(output)
                ToastManager.shared.show(message: String(localized: "Copied"), icon: "doc.on.clipboard.fill", success: true)
            } catch {
                presentError(error, message: String(localized: "The image couldn’t be copied."))
            }
        }
    }

    /// Shows a save panel and writes the result in the chosen format.
    func save() {
        guard !isExporting, !items.isEmpty else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [exportFormat == .png ? .png : .jpeg]
        panel.nameFieldStringValue = ScreenshotRenderer.defaultFileName(for: exportFormat)
        let accessory = NSHostingView(rootView: SaveFormatAccessory(model: self) { [weak panel] format in
            guard let panel else { return }
            panel.allowedContentTypes = [format == .png ? .png : .jpeg]
            let baseName = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        })
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory

        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.export(to: url)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    private func export(to url: URL) {
        isExporting = true
        let format = exportFormat
        let quality = jpegQuality
        Task {
            defer { isExporting = false }
            guard let output = await ScreenshotRenderer.render(config: config, items: items) else {
                presentError(message: String(localized: "The image couldn’t be rendered."))
                return
            }
            do {
                try await ScreenshotRenderer.write(output, to: url, format: format, jpegQuality: quality)
                ToastManager.shared.show(message: String(localized: "Saved"), icon: "checkmark.circle.fill", success: true)
            } catch {
                presentError(error, message: String(localized: "The image couldn’t be saved."))
            }
        }
    }

    private func presentError(_ error: Error? = nil, message: String) {
        if let error {
            Logger.editor.error("\(message, privacy: .public) \(error.localizedDescription, privacy: .public)")
        } else {
            Logger.editor.error("\(message, privacy: .public)")
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        if let error {
            alert.informativeText = error.localizedDescription
        }
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: Thumbnail & Drag Out

    private func scheduleThumbnailRefresh() {
        thumbnailTask?.cancel()
        thumbnailTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.exportThumbnail = ScreenshotRenderer.renderThumbnail(
                config: self.config,
                items: self.items,
                background: self.canvasBackgroundImage,
                maxPixelSize: 320
            )
        }
    }

    /// Prepares the file a drag-out will hand over (called when the pointer hovers the thumbnail).
    func prepareDragExport() {
        guard !isDragExportCurrent, dragExportTask == nil, !items.isEmpty else { return }
        let version = documentVersion
        let format = exportFormat
        let quality = jpegQuality
        dragExportTask = Task { [weak self] in
            guard let self else { return }
            defer { self.dragExportTask = nil }
            guard let output = await ScreenshotRenderer.render(config: config, items: items),
                  let url = Self.makeDragExportURL(format: format) else { return }
            do {
                try await ScreenshotRenderer.write(output, to: url, format: format, jpegQuality: quality)
                self.dragExport = (version, format, url)
            } catch {
                Logger.editor.error("Couldn't prepare the drag export: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private var isDragExportCurrent: Bool {
        guard let dragExport else { return false }
        return dragExport.version == documentVersion && dragExport.format == exportFormat
            && FileManager.default.fileExists(atPath: dragExport.url.path)
    }

    /// The item provider for dragging the result out (Finder, Mail, Slack…): a file in the export format.
    func dragItemProvider() -> NSItemProvider {
        if isDragExportCurrent, let url = dragExport?.url, let provider = NSItemProvider(contentsOf: url) {
            return provider
        }
        // The file isn't ready (the drag started right after an edit): render it now.
        let geometry = self.geometry
        let background = config.backgroundType == .image
            ? config.backgroundImage.url.flatMap { ImageLoadingService.cachedImageSync(at: $0, covering: geometry.pixelSize) }
            : nil
        guard let output = ScreenshotRenderer.render(config: config, items: items, geometry: geometry, background: background),
              let url = Self.makeDragExportURL(format: exportFormat) else { return NSItemProvider() }
        do {
            try ScreenshotRenderer.writeSync(output, to: url, format: exportFormat, jpegQuality: jpegQuality)
            dragExport = (documentVersion, exportFormat, url)
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        } catch {
            Logger.editor.error("Couldn't write the drag export: \(error.localizedDescription, privacy: .public)")
            return NSItemProvider()
        }
    }

    /// A fresh temporary file URL with the default export name (older drag exports are cleaned up).
    private static func makeDragExportURL(format: ExportFormat) -> URL? {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Clické Drag Exports", isDirectory: true)
        if let old = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) {
            let stale = old.filter {
                let created = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return created < Date.now.addingTimeInterval(-600)
            }
            stale.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Logger.editor.error("Couldn't create the drag export folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return folder.appendingPathComponent(ScreenshotRenderer.defaultFileName(for: format))
    }

    // MARK: - Commands

    /// Handles a keyboard command. Returns `false` if it doesn't apply (the key event then continues).
    func perform(_ command: EditorCommand) -> Bool {
        switch command {
        case .copy: copyToClipboard()
        case .save: save()
        case .close: window?.performClose(nil)
        case .undo: undo()
        case .redo: redo()
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .zoomToFit: zoomToFit()
        case .actualSize: zoomToActualSize()
        case .addImage: addImagesFromFile()
        case .toggleInspector:
            withEditorAnimation { isInspectorPresented.toggle() }
        case .deleteSelection:
            guard selectedItemID != nil, items.count > 1 else { return false }
            removeSelectedItem()
        case .deselect:
            guard selectedItemID != nil else { return false }
            selectedItemID = nil
        case .nudge(let dx, let dy):
            guard selectedItemID != nil else { return false }
            nudgeSelection(dx: dx, dy: dy)
        }
        return true
    }
}
