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

    var isInspectorPresented: Bool {
        didSet { EditorPreferences.isInspectorPresented = isInspectorPresented }
    }
    var inspectorTab: InspectorTab {
        didSet { EditorPreferences.inspectorTab = inspectorTab }
    }

    var redactionRequest: RedactionRequest?
    private(set) var isExporting = false
    /// Images being decoded off the main actor before they become layers.
    private(set) var pendingImportCount = 0

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

    /// Style given to new layers: the last style edited, remembered across captures.
    private var layerStyleTemplate: LayerStyle

    /// The document as last copied, saved or dragged out (or as it opened): closing the editor
    /// asks for confirmation when the document differs from it.
    @ObservationIgnored private var exportedSnapshot: EditorSnapshot?

    // MARK: Drag Export

    /// Folders of the files handed out by drag and drop, deleted when the editor closes.
    private var dragFileFolders: [URL] = []

    // MARK: - Initialization

    /// Creates an editor with `images` as its first layers. Images that can't be edited are
    /// reported; `hasContent` tells whether anything is left to show.
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
        self.isInspectorPresented = EditorPreferences.isInspectorPresented

        if case .file(let url) = config.backgroundImage {
            wallpapers.addImportedImage(at: url)
        }

        isRestoringSnapshot = true // the initial layers aren't an undoable change, nor an edit
        addImages(images)
        isRestoringSnapshot = false
        exportedSnapshot = snapshot
        updateBackgroundPreview()
        scheduleThumbnailRefresh()
    }

    /// Whether the editor has layers, or layers on the way.
    var hasContent: Bool { !items.isEmpty || pendingImportCount > 0 }

    // MARK: - Unexported Changes

    /// Whether the document changed since it was last copied, saved or dragged out.
    var hasUnexportedChanges: Bool { !items.isEmpty && snapshot != exportedSnapshot }

    private func markExported(_ exported: EditorSnapshot) {
        exportedSnapshot = exported
        updateDocumentEditedState()
    }

    /// The user chose "Don’t Save": the editor can close without asking again.
    func discardChanges() {
        markExported(snapshot)
    }

    /// The window's close button shows a dot while there are unexported changes.
    private func updateDocumentEditedState() {
        guard let window else { return }
        let edited = hasUnexportedChanges
        if window.isDocumentEdited != edited {
            window.isDocumentEdited = edited
        }
    }

    // MARK: - Document Changes

    private var snapshot: EditorSnapshot { EditorSnapshot(config: config, items: items) }

    private func documentDidChange(from previous: EditorSnapshot) {
        if !isRestoringSnapshot {
            history.willChange(from: previous)
            scheduleCommit()
            if let selected = selectedItem, selected.style != layerStyleTemplate {
                layerStyleTemplate = selected.style
            }
        }
        if CanvasGeometry(config: previous.config, items: previous.items).canvasSize != geometry.canvasSize {
            refitIfNeeded()
        }
        updateBackgroundPreview()
        scheduleThumbnailRefresh()
        updateDocumentEditedState()
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
        persistStyle()
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
        removeDragFiles()
        // The decoded backgrounds are only useful while an editor is open.
        ImageLoadingService.cache.removeAll()
    }

    // MARK: - Layers

    var selectedItem: CanvasItem? {
        guard let id = selectedItemID else { return nil }
        return items.first { $0.id == id }
    }

    private func index(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    /// Edits a layer in place (ignored if the layer was removed meanwhile).
    func updateItem(_ id: UUID, _ change: (inout CanvasItem) -> Void) {
        guard let index = index(of: id) else { return }
        change(&items[index])
    }

    /// Adds a bitmap as a new layer (selected, slightly offset from the previous ones).
    private func addLayer(_ image: ImportedImage) {
        var item = CanvasItem(image: LayerImage(image), style: layerStyleTemplate)
        let cascade = CGFloat(items.count) * 30
        item.offset = CGSize(width: cascade, height: cascade)
        item.zIndex = (items.map(\.zIndex).max() ?? -1) + 1
        items.append(item)
        selectedItemID = item.id
    }

    /// Adds images as new layers. Images above the layer size limit are downsampled off the main
    /// actor first; images that can't be edited are reported.
    /// - Returns: The number of layers added or on the way.
    @discardableResult
    func addImages(_ images: [NSImage]) -> Int {
        var added = 0
        var failure: Error?
        for image in images {
            do {
                switch try ImageImport.prepare(image) {
                case .ready(let imported):
                    addLayer(imported)
                case .needsDownsampling(let imported, let maxPixelSize):
                    importInBackground { ImageImport.downsample(imported, maxPixelSize: maxPixelSize) }
                }
                added += 1
            } catch {
                failure = error
            }
        }
        if let failure {
            presentImportError(failure)
        }
        return added
    }

    /// Adds image files as layers, decoded off the main actor.
    func addImages(at urls: [URL]) {
        for url in urls {
            importFile(at: url)
        }
    }

    /// Shows an open panel and adds the chosen images.
    func addImagesFromFile() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = String(localized: "Choose images to add to the canvas.")
        panel.prompt = String(localized: "Add")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.addImages(at: panel.urls)
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
                        self?.importFile(at: url)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor [weak self] in
                        self?.importData(data)
                    }
                }
            }
        }
        return accepted
    }

    // MARK: Importing

    /// Decodes an image file off the main actor (vector files go through `NSImage`, at a bounded size).
    private func importFile(at url: URL) {
        importInBackground(fileName: url.lastPathComponent, decode: {
            ImageImport.canDecode(contentsOf: url) ? try ImageImport.load(contentsOf: url) : nil
        }, fallback: {
            NSImage(contentsOf: url)
        })
    }

    /// Decodes dropped or pasted image data off the main actor.
    private func importData(_ data: Data) {
        importInBackground(fileName: nil, decode: {
            try? ImageImport.load(data: data)
        }, fallback: {
            NSImage(data: data)
        })
    }

    /// Runs `decode` off the main actor and adds the result. If it returns `nil`, the image is
    /// read with `fallback` (on the main actor, for formats only AppKit reads, such as PDF).
    private func importInBackground(
        fileName: String?,
        decode: @escaping @Sendable () throws -> ImportedImage?,
        fallback: @escaping () -> NSImage?
    ) {
        pendingImportCount += 1
        let isInitial = isRestoringSnapshot
        Task {
            defer { pendingImportCount -= 1 }
            do {
                if let imported = try await Self.runOffMainActor(decode) {
                    addImportedLayer(imported, isInitial: isInitial)
                    return
                }
                guard let image = fallback() else { throw ImageImportError.unreadable }
                switch try ImageImport.prepare(image) {
                case .ready(let imported):
                    addImportedLayer(imported, isInitial: isInitial)
                case .needsDownsampling(let imported, let maxPixelSize):
                    let small = try await Self.runOffMainActor { ImageImport.downsample(imported, maxPixelSize: maxPixelSize) }
                    addImportedLayer(small, isInitial: isInitial)
                }
            } catch {
                presentImportError(error, fileName: fileName)
            }
        }
    }

    private func importInBackground(_ work: @escaping @Sendable () -> ImportedImage) {
        importInBackground(fileName: nil, decode: work, fallback: { nil })
    }

    /// Adds a layer decoded in the background. One of the images the editor opened with
    /// (`isInitial`) isn't an undoable change, nor an edit to confirm on close.
    private func addImportedLayer(_ image: ImportedImage, isInitial: Bool) {
        guard isInitial else {
            addLayer(image)
            return
        }
        let wasExported = !hasUnexportedChanges
        isRestoringSnapshot = true
        addLayer(image)
        isRestoringSnapshot = false
        if wasExported {
            markExported(snapshot)
        }
    }

    @concurrent
    nonisolated private static func runOffMainActor<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
        try work()
    }

    private func presentImportError(_ error: Error, fileName: String? = nil) {
        Logger.editor.error("Couldn't import an image: \(error.localizedDescription, privacy: .private)")
        switch error {
        case ImageImportError.tooLarge:
            presentAlert(message: String(localized: "This image is too large to edit."), informativeText: fileName.map { String(localized: "“\($0)” has too many pixels to be edited.") })
        default:
            if let fileName {
                presentAlert(message: String(localized: "“\(fileName)” couldn’t be added."), informativeText: String(localized: "Only image files can be added to the canvas."))
            } else {
                presentAlert(message: String(localized: "The image couldn’t be added."), informativeText: error.localizedDescription)
            }
        }
    }

    /// The selected layer can be deleted (the last layer can't).
    var canDeleteSelection: Bool { items.count > 1 && selectedItem != nil }

    func removeSelectedItem() {
        guard canDeleteSelection, let id = selectedItemID else { return }
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
        items[index].scale = min(max(scale, CanvasItem.scaleRange.lowerBound), CanvasItem.scaleRange.upperBound)
    }

    /// Moves the selected layer by a few canvas points (arrow keys). Returns `false` if nothing is selected.
    @discardableResult
    func nudgeSelection(dx: CGFloat, dy: CGFloat) -> Bool {
        guard let id = selectedItemID, let index = index(of: id) else { return false }
        items[index].offset.width += dx
        items[index].offset.height += dy
        return true
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
        redactionRequest = RedactionRequest(itemID: item.id, image: item.image.makeNSImage())
    }

    /// Replaces the layer's bitmap with the redacted one. The sheet stays open if that fails.
    func applyRedaction(_ image: NSImage, toItem id: UUID) {
        guard let index = index(of: id) else {
            redactionRequest = nil
            return
        }
        let original = items[index].image
        let bitmap = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        guard let redacted = bitmap?.cgImage, redacted.width > 0, redacted.height > 0 else {
            Logger.editor.error("The redacted image has no bitmap.")
            presentAlert(
                message: String(localized: "The redaction couldn’t be applied."),
                informativeText: String(localized: "Your screenshot wasn’t changed. Try again, or cancel."),
                on: window?.attachedSheet
            )
            return
        }
        redactionRequest = nil
        guard redacted !== original.cgImage else { return } // nothing was redacted
        items[index].image = LayerImage(ImportedImage(cgImage: redacted, pointSize: original.pointSize))
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
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = String(localized: "Choose a background image.")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.urls.first else { return }
            selectWallpaper(wallpapers.addImportedImage(at: url))
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

    /// Copies the result to the clipboard: PNG, encoded off the main actor (TIFF is only produced
    /// if an app asks for it, see `PasteboardWriter`).
    func copyToClipboard() {
        guard !isExporting, !items.isEmpty, checkExportLimits() else { return }
        isExporting = true
        let exported = snapshot
        let previouslyExported = exportedSnapshot
        // Counts as exported right away, so closing the editor just after ⌘C doesn't ask.
        markExported(exported)
        Task {
            defer { isExporting = false }
            do {
                guard let output = await ScreenshotRenderer.render(config: exported.config, items: exported.items) else {
                    throw ScreenshotRenderer.ExportError.renderingFailed
                }
                let png = try await ScreenshotRenderer.pngData(for: output)
                guard PasteboardWriter.writePNG(png) else {
                    throw ScreenshotRenderer.ExportError.pasteboardRefused
                }
                ToastManager.shared.show(message: String(localized: "Copied to Clipboard"), icon: "doc.on.clipboard.fill", success: true)
            } catch {
                if exportedSnapshot == exported {
                    exportedSnapshot = previouslyExported
                    updateDocumentEditedState()
                }
                presentError(error, message: String(localized: "The image couldn’t be copied."))
            }
        }
    }

    /// Shows a save panel and writes the result in the chosen format.
    /// - Parameter completion: Called with `true` once the file is written, `false` if the user
    ///   cancelled or the export failed.
    func save(completion: ((Bool) -> Void)? = nil) {
        guard !isExporting, !items.isEmpty, let window, checkExportLimits() else {
            completion?(false)
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [exportFormat.contentType]
        panel.nameFieldStringValue = "\(ScreenCapture.baseFileName(for: .now)).\(exportFormat.fileExtension)"
        let accessory = NSHostingView(rootView: SaveFormatAccessory(model: self) { [weak panel] format in
            guard let panel else { return }
            panel.allowedContentTypes = [format.contentType]
            let baseName = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        })
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else {
                completion?(false)
                return
            }
            export(to: url, completion: completion)
        }
    }

    private func export(to url: URL, completion: ((Bool) -> Void)?) {
        isExporting = true
        let exported = snapshot
        let format = exportFormat
        let quality = jpegQuality
        Task {
            defer { isExporting = false }
            do {
                guard let output = await ScreenshotRenderer.render(config: exported.config, items: exported.items) else {
                    throw ScreenshotRenderer.ExportError.renderingFailed
                }
                try await ScreenshotRenderer.write(output, to: url, format: format, jpegQuality: quality)
                markExported(exported)
                let folder = FileManager.default.displayName(atPath: url.deletingLastPathComponent().path)
                ToastManager.shared.show(message: String(localized: "Saved to “\(folder)”"), icon: "checkmark.circle.fill", success: true)
                completion?(true)
            } catch {
                presentError(error, message: String(localized: "The image couldn’t be saved."))
                completion?(false)
            }
        }
    }

    /// Shows an alert and returns `false` if the export would exceed the size limits.
    private func checkExportLimits() -> Bool {
        let geometry = self.geometry
        guard !geometry.isWithinExportLimits else { return true }
        presentAlert(
            message: String(localized: "This image is too large to export."),
            informativeText: String(localized: "It would be \(geometry.pixelSizeDescription), and exports are limited to 16,384 pixels per side and 200 megapixels. Reduce the padding or the size of the images, or choose a canvas size.")
        )
        return false
    }

    private func presentError(_ error: Error? = nil, message: String) {
        if let error {
            Logger.editor.error("\(message, privacy: .public) \(error.localizedDescription, privacy: .private)")
        } else {
            Logger.editor.error("\(message, privacy: .public)")
        }
        presentAlert(message: message, informativeText: error?.localizedDescription)
    }

    /// Shows an alert as a sheet on the editor window (or on `host`), or a toast if there's no visible window.
    private func presentAlert(message: String, informativeText: String? = nil, on host: NSWindow? = nil) {
        guard let host = host ?? window, host.isVisible else {
            ToastManager.shared.show(message: message, icon: "exclamationmark.triangle.fill", success: false)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        if let informativeText {
            alert.informativeText = informativeText
        }
        alert.beginSheetModal(for: host)
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

    /// The item provider for dragging the result out (Finder, Mail, Slack…): a file in the export format.
    ///
    /// The image is rendered in memory when the drag starts; the file is encoded and written (in the
    /// app's private temporary folder) only if a drop asks for it, and deleted when the editor closes.
    func dragItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        guard !items.isEmpty, checkExportLimits() else { return provider }
        let exported = snapshot
        let format = exportFormat
        let baseName = ScreenCapture.baseFileName(for: .now)
        let render = Task { await ScreenshotRenderer.render(config: exported.config, items: exported.items) }
        provider.suggestedName = baseName
        provider.registerFileRepresentation(
            forTypeIdentifier: format.contentType.identifier,
            fileOptions: [],
            visibility: .all,
            loadHandler: Self.dragFileLoader(
                render: render,
                format: format,
                jpegQuality: jpegQuality,
                fileName: "\(baseName).\(format.fileExtension)"
            ) { [weak self] url in
                guard let self else { return }
                dragFileFolders.append(url.deletingLastPathComponent())
                markExported(exported)
            }
        )
        return provider
    }

    /// The load handler of a dragged file: waits for the render, encodes it off the main actor,
    /// then writes it through `CaptureTemporaryStorage`.
    nonisolated private static func dragFileLoader(
        render: Task<ScreenshotRenderer.Output?, Never>,
        format: ExportFormat,
        jpegQuality: Double,
        fileName: String,
        didWrite: @escaping @MainActor @Sendable (URL) -> Void
    ) -> @Sendable (@escaping @Sendable (URL?, Bool, (any Error)?) -> Void) -> Progress? {
        { completion in
            Task.detached(priority: .userInitiated) {
                do {
                    guard let output = await render.value else { throw ScreenshotRenderer.ExportError.renderingFailed }
                    let data = try ImageEncoder.data(for: output.image, format: format, jpegQuality: jpegQuality, pixelDensity: output.pixelDensity)
                    let url = try await MainActor.run {
                        let url = try CaptureTemporaryStorage.writeDragFile(data, named: fileName)
                        didWrite(url)
                        return url
                    }
                    completion(url, false, nil)
                } catch {
                    Logger.editor.error("Couldn't provide the dragged image: \(error.localizedDescription, privacy: .private)")
                    completion(nil, false, error)
                }
            }
            return nil
        }
    }

    /// Deletes the files handed out by drag and drop (receivers have their copy by now).
    private func removeDragFiles() {
        for folder in dragFileFolders {
            try? FileManager.default.removeItem(at: folder)
        }
        dragFileFolders.removeAll()
    }

    // MARK: - Commands

    /// Whether Copy, Save and drag-out are available.
    var canExport: Bool { !isExporting && !items.isEmpty }

    func toggleInspector() {
        withEditorAnimation { isInspectorPresented.toggle() }
    }

    /// File URLs of images (an image copied in Finder is pasted as the file, not as its icon).
    private static let imageFileReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]

    /// Whether the clipboard holds an image or an image file (checks the types only).
    var canPasteImage: Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: Self.imageFileReadingOptions)
            || pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
    }

    /// Adds the clipboard's images as new layers.
    func pasteImage() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: Self.imageFileReadingOptions) as? [URL], !urls.isEmpty {
            addImages(at: urls)
            return
        }
        var pasted = false
        for item in pasteboard.pasteboardItems ?? [] {
            guard let type = item.types.first(where: { UTType($0.rawValue)?.conforms(to: .image) == true }),
                  let data = item.data(forType: type) else { continue }
            importData(data)
            pasted = true
        }
        if !pasted {
            NSSound.beep()
        }
    }
}
