import AppKit
import SwiftUI

// MARK: - Transform

/// Maps between canvas coordinates (points) and the image's pixel space.
struct RedactionCanvasTransform {
    /// Where the image is drawn, in canvas points.
    let imageRect: CGRect
    /// Canvas points per image pixel.
    let scale: CGFloat

    /// Fits an image of `pixelSize` in `containerSize`, preserving its aspect ratio.
    init(pixelSize: CGSize, containerSize: CGSize, padding: CGFloat, maximumScale: CGFloat) {
        let available = CGSize(
            width: max(containerSize.width - padding * 2, 1),
            height: max(containerSize.height - padding * 2, 1)
        )
        let fit = min(available.width / max(pixelSize.width, 1), available.height / max(pixelSize.height, 1))
        let scale = min(fit, maximumScale)
        let size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        self.imageRect = CGRect(
            x: ((containerSize.width - size.width) / 2).rounded(),
            y: ((containerSize.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
        self.scale = scale
    }

    func pixelPoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - imageRect.minX) / scale, y: (point.y - imageRect.minY) / scale)
    }

    func viewRect(fromPixel rect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + rect.minX * scale,
            y: imageRect.minY + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// Converts a length in points to image pixels.
    func pixels(fromPoints points: CGFloat) -> CGFloat {
        points / max(scale, .ulpOfOne)
    }
}

// MARK: - Canvas

/// Shows the image with its redaction regions and handles drawing, selecting, moving and resizing them.
struct RedactionCanvasView: View {
    let model: RedactionEditorModel

    /// What the pointer is over. Only updated when it changes, so moving the pointer doesn't
    /// re-render the canvas.
    @State private var hoverTarget: RedactionHitTarget?
    @GestureState private var isPressing = false
    /// The canvas takes keyboard focus so Delete reaches it.
    @FocusState private var isFocused: Bool

    private static let coordinateSpace = "RedactionCanvas"
    /// Space around the image; presses that start here still draw, clamped to the image.
    private let padding: CGFloat = 24
    private let handleSize: CGFloat = 9
    private let handleHitRadius: CGFloat = 9
    /// Smallest region side, in points, kept when drawing or resizing.
    private let minimumSidePoints: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let transform = RedactionCanvasTransform(
                pixelSize: model.pixelSize,
                containerSize: proxy.size,
                padding: padding,
                // Don't enlarge beyond twice the image's point size.
                maximumScale: 2 / model.pixelsPerPoint
            )

            ZStack(alignment: .topLeading) {
                imageLayer(transform)
                effectsLayer(transform)
                outlinesLayer(transform)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .coordinateSpace(.named(Self.coordinateSpace))
            .gesture(pressGesture(transform), including: model.canEdit ? .all : .subviews)
            .onContinuousHover(coordinateSpace: .named(Self.coordinateSpace)) { phase in
                switch phase {
                case .active(let location): updateHover(hitTarget(at: location, transform))
                case .ended: updateHover(nil)
                }
            }
            .pointerStyle(pointerStyle)
        }
        .clipped()
        .overlay {
            if model.loadFailed {
                ContentUnavailableView("Can’t Open Image", systemImage: "photo", description: Text("The image couldn’t be read."))
            }
        }
        .onChange(of: isPressing) { _, pressing in
            // Also covers gestures cancelled without an end event.
            if !pressing { model.endInteraction() }
        }
        // The Delete key arrives as a delete command (deleteBackward:), forward delete as a key press.
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($isFocused)
        .onDeleteCommand { model.deleteSelection() }
        .onKeyPress(.deleteForward) {
            guard model.selectedID != nil else { return .ignored }
            model.deleteSelection()
            return .handled
        }
        .onAppear { isFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image")
        .accessibilityHint("Drag across the image to hide an area.")
    }

    // MARK: Layers

    /// The working copy of the pixels being redacted: never another representation of the
    /// image, and at most 2560 pixels long however large the original is.
    @ViewBuilder
    private func imageLayer(_ transform: RedactionCanvasTransform) -> some View {
        if let image = model.displayImage {
            let rect = transform.imageRect
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    /// The live preview of each region's effect.
    private func effectsLayer(_ transform: RedactionCanvasTransform) -> some View {
        ForEach(model.previewRegions) { region in
            if region.style == .solid {
                let rect = transform.viewRect(fromPixel: region.rect)
                Rectangle()
                    .fill(Color(.sRGB, white: region.fill.whiteLevel))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            } else if let patch = model.patches[region.id] {
                let rect = transform.viewRect(fromPixel: patch.sourceRect)
                Image(decorative: patch.image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Region outlines, the draft outline and the selection handles.
    @ViewBuilder
    private func outlinesLayer(_ transform: RedactionCanvasTransform) -> some View {
        let hovered = hoveredRegionID

        ForEach(Array(model.orderedRegions.enumerated()), id: \.element.id) { index, region in
            let rect = transform.viewRect(fromPixel: region.rect)
            RegionOutline(isSelected: region.id == model.selectedID, isHighlighted: region.id == hovered)
                .frame(width: rect.width, height: rect.height)
                .contextMenu { regionMenu(for: region) }
                .accessibilityElement()
                .accessibilityLabel(Text("Hidden area \(index + 1), \(Text(region.style.title))"))
                .accessibilityAddTraits(region.id == model.selectedID ? [.isSelected] : [])
                .accessibilityAction { model.select(region.id) }
                .accessibilityAction(named: "Delete") { model.delete(region.id) }
                .position(x: rect.midX, y: rect.midY)
        }

        if let draft = model.draft {
            let rect = transform.viewRect(fromPixel: draft.rect)
            Rectangle()
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }

        if let selected = model.selectedRegion {
            let rect = transform.viewRect(fromPixel: selected.rect)
            ForEach(RedactionCorner.allCases, id: \.self) { corner in
                let point = corner.point(in: rect)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: handleSize, height: handleSize)
                    .shadow(color: .black.opacity(0.3), radius: 1)
                    .position(x: point.x, y: point.y)
            }
            // Handles are hit-tested by the canvas gesture.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func regionMenu(for region: RedactionRegion) -> some View {
        Picker(
            "Style",
            selection: Binding(
                get: { region.style },
                set: { model.setStyle($0, forRegion: region.id) }
            )
        ) {
            ForEach(RedactionStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.inline)

        Divider()

        Button("Delete", role: .destructive) {
            model.delete(region.id)
        }
    }

    // MARK: Interaction

    private func pressGesture(_ transform: RedactionCanvasTransform) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
            .updating($isPressing) { _, isPressing, _ in
                isPressing = true
            }
            .onChanged { value in
                if model.interactionKind == nil {
                    isFocused = true
                    model.beginInteraction(
                        on: hitTarget(at: value.startLocation, transform),
                        at: transform.pixelPoint(fromView: value.startLocation),
                        minimumSide: transform.pixels(fromPoints: minimumSidePoints)
                    )
                }
                model.updateInteraction(to: transform.pixelPoint(fromView: value.location))
            }
            .onEnded { value in
                model.endInteraction()
                // Hover events pause during a drag; refresh what's under the pointer now.
                updateHover(hitTarget(at: value.location, transform))
            }
    }

    private func updateHover(_ target: RedactionHitTarget?) {
        if target != hoverTarget {
            hoverTarget = target
        }
    }

    private func hitTarget(at point: CGPoint, _ transform: RedactionCanvasTransform) -> RedactionHitTarget {
        if let selected = model.selectedRegion {
            let rect = transform.viewRect(fromPixel: selected.rect)
            let corner = RedactionCorner.allCases.first { corner in
                let handle = corner.point(in: rect)
                return hypot(handle.x - point.x, handle.y - point.y) <= handleHitRadius
            }
            if let corner {
                return .handle(selected.id, corner)
            }
        }
        if let region = model.orderedRegions.last(where: { transform.viewRect(fromPixel: $0.rect).insetBy(dx: -2, dy: -2).contains(point) }) {
            return .region(region.id)
        }
        return transform.imageRect.insetBy(dx: -padding / 2, dy: -padding / 2).contains(point) ? .image : .outside
    }

    private var hoveredRegionID: UUID? {
        guard model.interactionKind == nil else { return nil }
        switch hoverTarget {
        case .region(let id), .handle(let id, _): return id
        case .image, .outside, nil: return nil
        }
    }

    private var pointerStyle: PointerStyle? {
        guard model.canEdit, !model.isApplying else { return nil }
        switch model.interactionKind {
        case .drawing: return .rectSelection
        case .moving: return .grabActive
        case .resizing(let corner): return .frameResize(position: corner.resizePosition)
        case nil: break
        }

        switch hoverTarget {
        case .handle(_, let corner): return .frameResize(position: corner.resizePosition)
        case .region: return .grabIdle
        case .image: return .rectSelection
        case .outside, nil: return nil
        }
    }
}

// MARK: - Region Outline

/// Outline of a region: dashed when idle, accent-colored when selected.
private struct RegionOutline: View {
    let isSelected: Bool
    let isHighlighted: Bool

    var body: some View {
        Rectangle()
            .strokeBorder(
                isSelected ? Color.accentColor : Color.white.opacity(isHighlighted ? 1 : 0.85),
                style: StrokeStyle(lineWidth: isSelected || isHighlighted ? 2 : 1, dash: isSelected ? [] : [5, 3])
            )
            // Keeps the outline visible on light content.
            .shadow(color: .black.opacity(0.45), radius: 0.5)
            .contentShape(Rectangle())
    }
}

// MARK: - Helpers

private extension RedactionCorner {
    var resizePosition: FrameResizePosition {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}
