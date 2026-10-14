import AppKit
import CoreImage
import Foundation
import Observation
import os

// MARK: - Supporting Types

/// A corner of a region, used by the resize handles.
nonisolated enum RedactionCorner: CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    /// The corner's position in `rect` (top-left origin).
    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    var opposite: RedactionCorner {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }
}

/// What a pointer press on the canvas lands on.
nonisolated enum RedactionHitTarget: Equatable, Sendable {
    /// A resize handle of the selected region.
    case handle(UUID, RedactionCorner)
    /// The body of a region.
    case region(UUID)
    /// The image, outside any region: starts drawing a new one.
    case image
    /// The backdrop around the image.
    case outside
}

/// The pointer interaction in progress, as far as the UI is concerned.
nonisolated enum RedactionInteractionKind: Equatable, Sendable {
    case drawing
    case moving
    case resizing(RedactionCorner)
}

/// Transient feedback shown above the canvas.
nonisolated enum RedactionStatus: Equatable, Sendable {
    case found(Int)
    case alreadyHidden(Int)
    case nothingFound
    case detectionFailed
    case applyFailed

    var isError: Bool {
        switch self {
        case .detectionFailed, .applyFailed: true
        case .found, .alreadyHidden, .nothingFound: false
        }
    }

    var message: AttributedString {
        switch self {
        case .found(let count):
            AttributedString(localized: "Found ^[\(count) item](inflect: true). Review the image to make sure nothing was missed.")
        case .alreadyHidden(let count):
            AttributedString(localized: "Found ^[\(count) item](inflect: true), all already hidden. Review the image to make sure nothing was missed.")
        case .nothingFound:
            AttributedString(localized: "Nothing sensitive found. Review the image to make sure.")
        case .detectionFailed:
            AttributedString(localized: "Couldn’t read the text in this image.")
        case .applyFailed:
            AttributedString(localized: "Couldn’t apply the changes. Try again.")
        }
    }
}

// MARK: - Model

/// State and editing logic of the redaction sheet: regions, selection, undo history,
/// live preview, sensitive text detection and the final render.
///
/// Region geometry is in the image's pixel space (top-left origin), so it doesn't depend on
/// how large the image is displayed. Call `close()` when the sheet goes away: it stops
/// background work and releases the rendering resources.
@Observable
final class RedactionEditorModel {

    // MARK: Constants

    /// Longest side of the downscaled copy that is displayed and used for the live preview.
    private static let previewMaxDimension: CGFloat = 2560
    private static let maximumUndoSteps = 100
    private static let statusDuration: Duration = .seconds(8)
    private static let draftID = UUID()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "clicke", category: "Redaction")

    private enum Interaction {
        case drawing(anchor: CGPoint)
        case moving(id: UUID, startRect: CGRect, startPoint: CGPoint)
        case resizing(id: UUID, corner: RedactionCorner, anchor: CGPoint)
    }

    // MARK: Source

    let image: NSImage
    /// Size of the image in pixels.
    private(set) var pixelSize: CGSize
    /// Source pixels per point (2 for Retina screenshots).
    private(set) var pixelsPerPoint: CGFloat = 1
    /// The pixels being redacted. Everything shown and rendered comes from them, so the sheet
    /// can't show another representation of the image than the one that is changed.
    @ObservationIgnored private var cgImage: CGImage?
    /// Whether the image is ready; editing is disabled otherwise.
    private(set) var canEdit = false
    /// Whether the image couldn't be decoded.
    private(set) var loadFailed = false

    // MARK: Regions

    private(set) var regions: [RedactionRegion] = [] {
        didSet { setNeedsPreview() }
    }
    /// The region being drawn, shown live before it's committed.
    private(set) var draft: RedactionRegion? {
        didSet { setNeedsPreview() }
    }
    private(set) var selectedID: UUID?
    /// Style used for new regions; mirrors the selected region's style.
    private(set) var settings = RedactionToolSettings()
    private var interaction: Interaction?
    @ObservationIgnored private var minimumSide: CGFloat = 1

    // MARK: Undo

    private var undoStack: [[RedactionRegion]] = []
    private var redoStack: [[RedactionRegion]] = []
    /// Regions before a coalesced change (drag, slider) began.
    @ObservationIgnored private var pendingUndoState: [RedactionRegion]?

    // MARK: Preview

    /// The image as displayed: the working copy, at most `previewMaxDimension` pixels long.
    private(set) var displayImage: CGImage?
    /// Rendered effects for the preview, keyed by region ID.
    private(set) var patches: [UUID: ImageRedactor.PreviewPatch] = [:]
    @ObservationIgnored private var workingCopy: ImageRedactor.WorkingCopy?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewIsStale = false
    /// Core Image context for the preview and the final render, released by `close()`.
    @ObservationIgnored private var renderContext: CIContext?
    @ObservationIgnored private var isClosed = false

    // MARK: Status

    private(set) var isDetecting = false
    private(set) var isApplying = false
    private(set) var status: RedactionStatus?
    @ObservationIgnored private var detectionTask: Task<Void, Never>?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Cheap: decoding is deferred to `prepare()`, since SwiftUI may create models it discards.
    init(image: NSImage) {
        self.image = image
        self.pixelSize = Self.estimatedPixelSize(of: image)
    }

    /// The image's bitmap at full resolution, through the editor's bounded import (vector images
    /// are rasterized at a bounded size).
    private static func fullResolutionImage(of image: NSImage) -> CGImage? {
        switch try? ImageImport.prepare(image) {
        case .ready(let imported)?, .needsDecoding(let imported, _)?:
            return imported.cgImage
        case nil:
            return nil
        }
    }

    /// Decodes the image and builds the working copy that is displayed and previewed.
    func prepare() async {
        guard cgImage == nil, !loadFailed, !isClosed else { return }
        guard let decoded = Self.fullResolutionImage(of: image) else {
            Self.logger.error("Couldn't get pixels for the image to redact")
            loadFailed = true
            return
        }
        cgImage = decoded
        pixelSize = CGSize(width: decoded.width, height: decoded.height)
        pixelsPerPoint = image.size.width > 0 ? max(CGFloat(decoded.width) / image.size.width, 1) : 1

        let copy = await ImageRedactor.makeWorkingCopy(
            of: decoded,
            maxDimension: Self.previewMaxDimension,
            pixelsPerPoint: pixelsPerPoint
        )
        guard !isClosed else { return }
        workingCopy = copy
        displayImage = copy.image
        canEdit = true
        setNeedsPreview()
    }

    /// Stops background work, including a render in progress, and releases the rendering
    /// resources. Call it when the sheet goes away.
    func close() {
        isClosed = true
        cancelApply()
        detectionTask?.cancel()
        previewTask?.cancel()
        statusTask?.cancel()
        renderContext = nil
        workingCopy = nil
        patches = [:]
    }

    // MARK: - Queries

    var selectedRegion: RedactionRegion? {
        regions.first { $0.id == selectedID }
    }

    /// Regions from bottom to top, in rendering order.
    var orderedRegions: [RedactionRegion] {
        RedactionRegion.compositingOrder(regions)
    }

    /// Regions to preview, including the one being drawn, in rendering order.
    var previewRegions: [RedactionRegion] {
        RedactionRegion.compositingOrder(regions + (draft.map { [$0] } ?? []))
    }

    var interactionKind: RedactionInteractionKind? {
        switch interaction {
        case .drawing: .drawing
        case .moving: .moving
        case .resizing(_, let corner, _): .resizing(corner)
        case nil: nil
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Whether there are marked areas that closing the sheet would discard.
    var hasUnappliedChanges: Bool { !regions.isEmpty }

    /// Whether Apply is available. Not while detection runs, so no detected area can be left out.
    var canApply: Bool { canEdit && !isApplying && !isDetecting }

    /// Whether to explain how to get started.
    var showsHint: Bool { canEdit && regions.isEmpty && draft == nil && status == nil && !isDetecting }

    /// Regions can't change while the image isn't ready or the result is being rendered.
    private var isLocked: Bool { !canEdit || isApplying }

    // MARK: - Pointer Interaction

    /// Starts a press on `target` at `point` (image pixels).
    /// - Parameter minimumSide: Smallest region side, in pixels, kept when drawing or resizing.
    func beginInteraction(on target: RedactionHitTarget, at point: CGPoint, minimumSide: CGFloat) {
        guard !isLocked else { return }
        endInteraction()
        self.minimumSide = max(minimumSide, 1)

        switch target {
        case .handle(let id, let corner):
            guard let region = region(withID: id) else { return }
            beginChange()
            interaction = .resizing(id: id, corner: corner, anchor: corner.opposite.point(in: region.rect))
        case .region(let id):
            guard let region = region(withID: id) else { return }
            select(id)
            beginChange()
            interaction = .moving(id: id, startRect: region.rect, startPoint: point)
        case .image:
            select(nil)
            interaction = .drawing(anchor: clamped(point))
        case .outside:
            select(nil)
        }
    }

    /// Continues the current press with the pointer at `point` (image pixels).
    func updateInteraction(to point: CGPoint) {
        switch interaction {
        case .drawing(let anchor):
            let rect = Self.rect(from: anchor, to: clamped(point))
            draft = rect.width >= 1 && rect.height >= 1
                ? RedactionRegion(id: Self.draftID, rect: rect, settings: settings)
                : nil

        case .moving(let id, let startRect, let startPoint):
            var rect = startRect.offsetBy(dx: point.x - startPoint.x, dy: point.y - startPoint.y)
            rect.origin.x = min(max(rect.minX, 0), pixelSize.width - rect.width)
            rect.origin.y = min(max(rect.minY, 0), pixelSize.height - rect.height)
            updateRegion(id) { $0.rect = rect.integral }

        case .resizing(let id, _, let anchor):
            let rect = resizedRect(anchor: anchor, to: clamped(point))
            updateRegion(id) { $0.rect = rect }

        case nil:
            break
        }
    }

    /// Finishes the current press, committing the drawn region or the move/resize to the undo history.
    func endInteraction() {
        guard let interaction else { return }
        self.interaction = nil

        switch interaction {
        case .drawing:
            guard let draft else { return }
            self.draft = nil
            guard draft.rect.width >= minimumSide, draft.rect.height >= minimumSide else { return }
            let region = RedactionRegion(rect: draft.rect.integral, settings: draft.settings)
            // Reuse the live preview so the committed region doesn't flicker.
            if let patch = patches.removeValue(forKey: Self.draftID) {
                patches[region.id] = ImageRedactor.PreviewPatch(id: region.id, key: patch.key, image: patch.image, sourceRect: patch.sourceRect)
            }
            recordChange { regions.append(region) }
            selectedID = region.id

        case .moving, .resizing:
            endChange()
        }
    }

    // MARK: - Editing

    func select(_ id: UUID?) {
        selectedID = id
        if let region = selectedRegion {
            settings = region.settings
        }
    }

    func setStyle(_ style: RedactionStyle) {
        guard !isLocked else { return }
        settings.style = style
        updateSelectedRegion { $0.style = style }
    }

    /// Changes the style of a specific region (context menu).
    func setStyle(_ style: RedactionStyle, forRegion id: UUID) {
        guard !isLocked else { return }
        recordChange { updateRegion(id) { $0.style = style } }
        if id == selectedID { settings.style = style }
    }

    /// Sets the effect strength. Wrap continuous changes in `beginChange()`/`endChange()`.
    func setStrength(_ strength: Double) {
        guard !isLocked else { return }
        settings.strength = min(max(strength, 0), 1)
        updateSelectedRegion { $0.strength = settings.strength }
    }

    func setFill(_ fill: RedactionFill) {
        guard !isLocked else { return }
        settings.fill = fill
        updateSelectedRegion { $0.fill = fill }
    }

    func delete(_ id: UUID) {
        guard !isLocked else { return }
        recordChange { regions.removeAll { $0.id == id } }
        if selectedID == id { selectedID = nil }
    }

    func deleteSelection() {
        guard !isLocked, let selectedID else { return }
        delete(selectedID)
    }

    func clearAll() {
        guard !isLocked else { return }
        endInteraction()
        recordChange { regions.removeAll() }
        selectedID = nil
    }

    // MARK: - Undo

    /// Groups the following changes into a single undo step until `endChange()`.
    func beginChange() {
        if pendingUndoState == nil {
            pendingUndoState = regions
        }
    }

    func endChange() {
        guard let before = pendingUndoState else { return }
        pendingUndoState = nil
        if before != regions {
            pushUndo(before)
        }
    }

    func undo() {
        guard !isLocked else { return }
        endInteraction()
        endChange()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(regions)
        regions = previous
        validateSelection()
    }

    func redo() {
        guard !isLocked else { return }
        endInteraction()
        endChange()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(regions)
        regions = next
        validateSelection()
    }

    private func recordChange(_ change: () -> Void) {
        let before = regions
        change()
        guard pendingUndoState == nil, before != regions else { return }
        pushUndo(before)
    }

    private func pushUndo(_ state: [RedactionRegion]) {
        undoStack.append(state)
        if undoStack.count > Self.maximumUndoSteps {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    private func validateSelection() {
        if let selectedID, region(withID: selectedID) == nil {
            self.selectedID = nil
        }
    }

    // MARK: - Sensitive Text

    /// Recognizes text on device and adds a region over each sensitive item. Secrets, card
    /// numbers and IBANs get a solid fill; other items use the current style.
    func findSensitiveText() {
        guard !isDetecting, !isLocked, let cgImage else { return }
        isDetecting = true
        show(nil)

        detectionTask = Task {
            defer { isDetecting = false }
            do {
                let matches = try await SensitiveTextDetector.detect(in: cgImage)
                try Task.checkCancellation()
                addDetectedRegions(matches)
            } catch is CancellationError {
                // The sheet closed.
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("Text recognition failed: \(error.localizedDescription, privacy: .public)")
                show(.detectionFailed)
            }
        }
    }

    private func addDetectedRegions(_ matches: [SensitiveTextMatch]) {
        guard !matches.isEmpty else {
            show(.nothingFound)
            return
        }

        var added: [RedactionRegion] = []
        for match in matches {
            let covered = (regions + added).contains { Self.coverage(of: match.rect, by: $0.rect) > 0.9 }
            if !covered {
                added.append(RedactionRegion(rect: match.rect, settings: detectionSettings(for: match.kind)))
            }
        }

        if added.isEmpty {
            show(.alreadyHidden(matches.count))
        } else {
            recordChange { regions.append(contentsOf: added) }
            show(.found(matches.count))
        }
    }

    /// The style of a region added over detected text of `kind`.
    private func detectionSettings(for kind: SensitiveTextKind) -> RedactionToolSettings {
        var detected = settings
        if kind.needsSolidFill {
            detected.style = .solid
        }
        return detected
    }

    // MARK: - Apply

    /// Renders the regions into the image at full resolution, off the main actor.
    ///
    /// `completion` receives the redacted image, with the same point size, pixel size and
    /// color space as the original, or nil when there is nothing to hide. It isn't called if
    /// rendering fails, or if `cancelApply()` or `close()` runs first.
    func apply(completion: @escaping (NSImage?) -> Void) {
        guard canApply, let cgImage else { return }
        endInteraction()
        guard !regions.isEmpty else {
            completion(nil)
            return
        }

        // Set before the render starts, so a second Return can't start another one.
        isApplying = true
        show(nil)
        let regions = regions
        let pixelsPerPoint = pixelsPerPoint
        let context = context()
        applyTask = Task {
            let output = await ImageRedactor.redacting(cgImage, regions: regions, pixelsPerPoint: pixelsPerPoint, context: context)
            // Cancelled: `cancelApply()` already reset the state.
            guard !Task.isCancelled else { return }
            isApplying = false
            applyTask = nil
            guard let output else {
                show(.applyFailed)
                return
            }
            completion(Self.bitmapImage(output, pointSize: image.size))
        }
    }

    /// Stops a render in progress; its result is dropped.
    func cancelApply() {
        applyTask?.cancel()
        applyTask = nil
        isApplying = false
    }

    /// An image backed by a bitmap of `cgImage`, with the given point size. Unlike
    /// `NSImage(cgImage:size:)`, it keeps the pixels and color space as they are.
    private static func bitmapImage(_ cgImage: CGImage, pointSize: CGSize) -> NSImage {
        let representation = NSBitmapImageRep(cgImage: cgImage)
        let size = pointSize.width > 0 && pointSize.height > 0
            ? pointSize
            : CGSize(width: cgImage.width, height: cgImage.height)
        representation.size = size
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    // MARK: - Preview Rendering

    /// Re-renders the preview patches that changed. Renders run one at a time; changes made
    /// meanwhile are picked up by the next pass, so dragging stays smooth.
    private func setNeedsPreview() {
        previewIsStale = true
        guard previewTask == nil, workingCopy != nil, !isClosed else { return }
        previewTask = Task {
            await renderStalePreviews()
            previewTask = nil
        }
    }

    private func renderStalePreviews() async {
        while previewIsStale, !Task.isCancelled, let workingCopy {
            previewIsStale = false

            var requests: [ImageRedactor.PatchRequest] = []
            var liveIDs = Set<UUID>()
            for region in previewRegions {
                guard let key = ImageRedactor.patchKey(for: region, in: workingCopy) else { continue }
                liveIDs.insert(region.id)
                if patches[region.id]?.key != key {
                    requests.append(ImageRedactor.PatchRequest(id: region.id, key: key))
                }
            }
            if patches.keys.contains(where: { !liveIDs.contains($0) }) {
                patches = patches.filter { liveIDs.contains($0.key) }
            }
            guard !requests.isEmpty else { continue }

            let rendered = await ImageRedactor.renderPreviewPatches(requests, in: workingCopy, context: context())
            guard !Task.isCancelled else { return }
            var updated = patches
            for patch in rendered {
                updated[patch.id] = patch
            }
            patches = updated
        }
    }

    // MARK: - Helpers

    /// The Core Image context of this session, created on first use.
    private func context() -> CIContext {
        if let renderContext {
            return renderContext
        }
        let context = ImageRedactor.makeContext()
        // Not kept once closed, so a late render can't bring it back.
        if !isClosed {
            renderContext = context
        }
        return context
    }

    private func show(_ status: RedactionStatus?) {
        statusTask?.cancel()
        self.status = status
        guard status != nil else { return }
        statusTask = Task {
            try? await Task.sleep(for: Self.statusDuration)
            guard !Task.isCancelled else { return }
            self.status = nil
        }
    }

    private func region(withID id: UUID) -> RedactionRegion? {
        regions.first { $0.id == id }
    }

    private func updateRegion(_ id: UUID, _ update: (inout RedactionRegion) -> Void) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        update(&regions[index])
    }

    private func updateSelectedRegion(_ update: (inout RedactionRegion) -> Void) {
        guard let selectedID else { return }
        recordChange { updateRegion(selectedID, update) }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), pixelSize.width), y: min(max(point.y, 0), pixelSize.height))
    }

    /// The rectangle from a fixed anchor to the pointer, kept at least `minimumSide` wide and tall.
    private func resizedRect(anchor: CGPoint, to point: CGPoint) -> CGRect {
        var end = point
        if abs(end.x - anchor.x) < minimumSide {
            end.x = anchor.x + (end.x >= anchor.x ? minimumSide : -minimumSide)
        }
        if abs(end.y - anchor.y) < minimumSide {
            end.y = anchor.y + (end.y >= anchor.y ? minimumSide : -minimumSide)
        }
        return Self.rect(from: anchor, to: clamped(end)).integral
    }

    private static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Fraction of `rect`'s area covered by `other`.
    private static func coverage(of rect: CGRect, by other: CGRect) -> CGFloat {
        let intersection = rect.intersection(other)
        guard !intersection.isNull, rect.width > 0, rect.height > 0 else { return 0 }
        return (intersection.width * intersection.height) / (rect.width * rect.height)
    }

    /// Pixel size from the image representations, without decoding.
    private static func estimatedPixelSize(of image: NSImage) -> CGSize {
        let largest = image.representations.max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        if let largest, largest.pixelsWide > 0, largest.pixelsHigh > 0 {
            return CGSize(width: largest.pixelsWide, height: largest.pixelsHigh)
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    }
}
