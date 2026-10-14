import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The editor's main area: the live canvas on a neutral workspace, with zoom, pan,
/// layer selection / dragging / resizing, and image drop.
struct ScreenshotPreviewCanvas: View {
    let model: ScreenshotEditorViewModel

    @State private var panStart: CGSize?
    @State private var magnificationStartZoom: CGFloat?
    @State private var isDropTargeted = false

    /// Coordinate space of the drawn canvas (origin at its top-left corner).
    static let coordinateSpace = "EditorCanvas"

    var body: some View {
        GeometryReader { proxy in
            let viewport = proxy.size
            let zoom = model.zoom
            let geometry = model.geometry
            let canvasSize = CGSize(width: geometry.canvasSize.width * zoom, height: geometry.canvasSize.height * zoom)

            ZStack {
                // The workspace: drag to pan, click to deselect, double-click to fit.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .onTapGesture(count: 2) { model.zoomToFit() }
                    .onTapGesture { model.selectedItemID = nil }

                CanvasStage(model: model, geometry: geometry, zoom: zoom, canvasSize: canvasSize)
                    .position(x: viewport.width / 2 + model.pan.width, y: viewport.height / 2 + model.pan.height)
            }
            .frame(width: viewport.width, height: viewport.height)
            .simultaneousGesture(magnifyGesture)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            model.viewportDidChange(to: size)
        }
        .clipped()
        .background {
            ScrollWheelMonitor { event, location in
                model.handleScroll(event, at: location)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).ignoresSafeArea())
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            model.handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Canvas")
    }

    // MARK: Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = panStart ?? model.pan
                if panStart == nil { panStart = start }
                model.setPan(CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height))
            }
            .onEnded { _ in
                panStart = nil
            }
    }

    /// Pinch to zoom, relative to the zoom at the start of the gesture, around the pinch location.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = magnificationStartZoom ?? model.zoom
                if magnificationStartZoom == nil { magnificationStartZoom = start }
                model.setZoom(start * value.magnification, anchor: value.startLocation)
            }
            .onEnded { _ in
                magnificationStartZoom = nil
            }
    }
}

// MARK: - Canvas Stage

/// The canvas itself (background + layers, clipped like the export) and the selection on top.
private struct CanvasStage: View {
    let model: ScreenshotEditorViewModel
    let geometry: CanvasGeometry
    let zoom: CGFloat
    let canvasSize: CGSize

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                CanvasBackgroundView(
                    config: model.config,
                    image: model.canvasBackgroundImage,
                    size: canvasSize,
                    scale: zoom,
                    showsCheckerboard: true
                )
                .allowsHitTesting(false) // clicks on the background reach the workspace

                ForEach(model.items.sorted { $0.zIndex < $1.zIndex }) { item in
                    CanvasLayer(
                        model: model,
                        item: item,
                        unit: geometry.layerScale(for: item) * zoom,
                        center: geometry.center(of: item, scale: zoom),
                        zoom: zoom
                    )
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()

            if let selected = model.selectedItem {
                SelectionOverlay(
                    model: model,
                    item: selected,
                    unit: geometry.layerScale(for: selected) * zoom,
                    center: geometry.center(of: selected, scale: zoom)
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .coordinateSpace(.named(ScreenshotPreviewCanvas.coordinateSpace))
        .background {
            // Lifts the canvas off the workspace (cheap: a shape shadow, not a shadow of the content).
            Rectangle()
                .fill(colorScheme == .dark ? Color.black : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 12, y: 3)
                .allowsHitTesting(false) // empty canvas areas behave like the workspace
        }
    }
}

// MARK: - Layer

/// A layer on the live canvas: click to select, drag to move.
private struct CanvasLayer: View {
    let model: ScreenshotEditorViewModel
    let item: CanvasItem
    /// Screen points per layer point.
    let unit: CGFloat
    let center: CGPoint
    let zoom: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var dragStartOffset: CGSize?

    var body: some View {
        let pixelWidth = item.image.pointSize.width * unit * displayScale
        LayerView(item: item, image: item.image.bitmap(forDisplayPixelWidth: pixelWidth), unit: unit)
            .gesture(dragGesture)
            .pointerStyle(dragStartOffset == nil ? .grabIdle : .grabActive)
            .position(center)
            .accessibilityElement()
            .accessibilityLabel("Screenshot")
            .accessibilityAddTraits(model.selectedItemID == item.id ? [.isImage, .isSelected] : .isImage)
            .accessibilityAction { model.selectedItemID = item.id }
    }

    /// Starts on mouse down (so a click selects), moves the layer while dragging, one undo step.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(ScreenshotPreviewCanvas.coordinateSpace))
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = item.offset
                    model.selectedItemID = item.id
                    model.beginInteraction()
                }
                guard let start = dragStartOffset,
                      abs(value.translation.width) + abs(value.translation.height) > 0 else { return }
                model.setOffset(
                    CGSize(width: start.width + value.translation.width / zoom, height: start.height + value.translation.height / zoom),
                    forItem: item.id
                )
            }
            .onEnded { _ in
                dragStartOffset = nil
                model.endInteraction()
            }
    }
}

// MARK: - Selection

/// Accent outline and corner handles around the selected layer (drag a handle to resize).
private struct SelectionOverlay: View {
    let model: ScreenshotEditorViewModel
    let item: CanvasItem
    let unit: CGFloat
    let center: CGPoint

    var body: some View {
        let size = CGSize(width: item.framedSize.width * unit, height: item.framedSize.height * unit)
        let radius = item.style.outerCornerRadius * unit

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius + 1, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(-1)
                .allowsHitTesting(false)

            ForEach(HandleCorner.allCases) { corner in
                ResizeHandle(model: model, item: item, corner: corner, layerCenter: center)
                    .position(x: corner.x * size.width, y: corner.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(LayerTransform(item: item))
        .position(center)
    }
}

private enum HandleCorner: CaseIterable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var id: Self { self }
    var x: CGFloat { self == .topLeading || self == .bottomLeading ? 0 : 1 }
    var y: CGFloat { self == .topLeading || self == .topTrailing ? 0 : 1 }

    var resizePosition: FrameResizePosition {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }
}

/// A corner handle. Resizes proportionally, from the layer's center.
private struct ResizeHandle: View {
    let model: ScreenshotEditorViewModel
    let item: CanvasItem
    let corner: HandleCorner
    let layerCenter: CGPoint

    @State private var start: (scale: Double, distance: CGFloat)?

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
            .frame(width: 9, height: 9)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: corner.resizePosition))
            .gesture(resizeGesture)
            .accessibilityHidden(true)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(ScreenshotPreviewCanvas.coordinateSpace))
            .onChanged { value in
                if start == nil {
                    start = (item.scale, distance(value.startLocation))
                    model.beginInteraction()
                }
                guard let start, start.distance > 1 else { return }
                model.setScale(start.scale * Double(distance(value.location) / start.distance), forItem: item.id)
            }
            .onEnded { _ in
                start = nil
                model.endInteraction()
            }
    }

    private func distance(_ point: CGPoint) -> CGFloat {
        hypot(point.x - layerCenter.x, point.y - layerCenter.y)
    }
}

// MARK: - Scroll Wheel

/// Forwards scroll-wheel / trackpad scroll events over this view's frame (SwiftUI has no scroll-wheel gesture).
/// It never takes part in hit testing, so clicks go through.
struct ScrollWheelMonitor: NSViewRepresentable {
    let onScroll: (NSEvent, CGPoint) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onScroll = onScroll
    }

    final class MonitorView: NSView {
        var onScroll: ((NSEvent, CGPoint) -> Void)?
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // Local monitors are called on the main thread.
                let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return handled ? nil : event
            }
        }

        /// Forwards the event if it happened over this view. Returns `true` if it was consumed.
        private func handle(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, window.attachedSheet == nil, let onScroll else { return false }
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return false }
            onScroll(event, point)
            return true
        }
    }
}
