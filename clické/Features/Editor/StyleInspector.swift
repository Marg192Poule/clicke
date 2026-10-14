import SwiftUI

/// Edits the selected layer in place (on the model's current value).
typealias LayerUpdate = ((inout CanvasItem) -> Void) -> Void

/// The Style page: layers, then the selected layer's frame, corners, shadow and transform.
///
/// The sections are `Equatable` views fed with plain values, so dragging a slider only redraws
/// that slider. They're re-created (`.id`) when another layer gets selected.
struct StyleInspector: View {
    let model: ScreenshotEditorViewModel

    var body: some View {
        if model.items.count > 1 {
            LayersSection(
                model: model,
                rows: LayersSection.rows(for: model.items),
                selection: model.selectedItemID,
                canDelete: model.canDeleteSelection
            )
            .equatable()
        }

        if let item = model.selectedItem {
            let id = item.id
            let update: LayerUpdate = { change in model.updateItem(id, change) }
            Group {
                FrameSection(
                    mockup: item.style.mockup,
                    frameWidth: item.style.frameWidth,
                    borderColor: item.style.borderColor,
                    windowAppearance: item.style.windowAppearance,
                    update: update
                )
                .equatable()
                CornersSection(radius: item.style.cornerRadius, update: update)
                    .equatable()
                ShadowSection(shadow: item.style.shadow, update: update)
                    .equatable()
                TransformSection(
                    scale: item.scale,
                    rotation: item.rotation,
                    rotationX: item.rotationX,
                    rotationY: item.rotationY,
                    update: update
                )
                .equatable()
            }
            .id(id)
        } else {
            Section {
                ContentUnavailableView(
                    "No Image Selected",
                    systemImage: "cursorarrow.click",
                    description: Text("Click an image on the canvas to edit its style.")
                )
            }
        }
    }
}

// MARK: - Layers

private struct LayersSection: View, Equatable {
    struct Row: Equatable, Identifiable {
        let id: UUID
        /// "Layer 2": layers are numbered in the order they were added.
        let number: Int
        let thumbnail: CGImage
    }

    let model: ScreenshotEditorViewModel
    /// Front to back.
    let rows: [Row]
    let selection: UUID?
    let canDelete: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rows == rhs.rows && lhs.selection == rhs.selection && lhs.canDelete == rhs.canDelete
    }

    static func rows(for items: [CanvasItem]) -> [Row] {
        items.enumerated()
            .sorted { $0.element.zIndex > $1.element.zIndex }
            .map { Row(id: $0.element.id, number: $0.offset + 1, thumbnail: $0.element.image.preview ?? $0.element.image.cgImage) }
    }

    var body: some View {
        Section("Layers") {
            ForEach(rows) { row in
                let isSelected = selection == row.id
                Button {
                    model.selectedItemID = row.id
                } label: {
                    HStack(spacing: 10) {
                        Image(decorative: row.thumbnail, scale: 1)
                            .resizable()
                            .interpolation(.medium)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        Text("Layer \(row.number)")
                            .fontWeight(isSelected ? .semibold : .regular)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .contextMenu {
                    Button("Copy") {
                        model.copyToClipboard()
                    }
                    Button("Redact…") {
                        model.selectedItemID = row.id
                        model.redactSelectedLayer()
                    }
                    Button("Bring to Front") {
                        model.selectedItemID = row.id
                        model.bringSelectedToFront()
                    }
                    Button("Send to Back") {
                        model.selectedItemID = row.id
                        model.sendSelectedToBack()
                    }
                    Divider()
                    Button("Delete Layer", role: .destructive) {
                        model.selectedItemID = row.id
                        model.removeSelectedItem()
                    }
                }
                .accessibilityLabel(Text("Layer \(row.number)"))
            }

            HStack {
                ControlGroup {
                    Button {
                        model.bringSelectedToFront()
                    } label: {
                        Label("Bring to Front", systemImage: "square.3.layers.3d.top.filled")
                    }
                    .help("Bring the selected layer to the front")
                    Button {
                        model.sendSelectedToBack()
                    } label: {
                        Label("Send to Back", systemImage: "square.3.layers.3d.bottom.filled")
                    }
                    .help("Send the selected layer to the back")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
                .disabled(selection == nil)

                Spacer()

                Button("Apply Style to All") {
                    model.applySelectedStyleToAllLayers()
                }
                .disabled(selection == nil)
                .help("Give every layer the frame, corners and shadow of the selected one")

                Button(role: .destructive) {
                    model.removeSelectedItem()
                } label: {
                    Label("Delete Layer", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Delete the selected layer (⌫)")
                .disabled(!canDelete)
            }
        }
    }
}

// MARK: - Frame

private struct FrameSection: View, Equatable {
    let mockup: MockupStyle
    let frameWidth: Double
    let borderColor: RGBAColor
    let windowAppearance: WindowChromeAppearance
    let update: LayerUpdate

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.mockup == rhs.mockup && lhs.frameWidth == rhs.frameWidth
            && lhs.borderColor == rhs.borderColor && lhs.windowAppearance == rhs.windowAppearance
    }

    var body: some View {
        Section("Frame") {
            HStack(spacing: 8) {
                ForEach(MockupStyle.allCases) { style in
                    CaptionedTile(title: Text(style.displayName), isSelected: mockup == style) {
                        update { $0.style.mockup = style }
                    } content: {
                        MockupThumbnail(style: style)
                            .frame(height: 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            switch mockup {
            case .none:
                EmptyView()
            case .glass:
                widthSlider
            case .border:
                widthSlider
                ColorPicker(
                    "Color",
                    selection: Binding(get: { borderColor.color }, set: { color in update { $0.style.borderColor = RGBAColor(color) } }),
                    supportsOpacity: false
                )
            case .window:
                Picker("Title bar", selection: Binding(get: { windowAppearance }, set: { appearance in update { $0.style.windowAppearance = appearance } })) {
                    ForEach(WindowChromeAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var widthSlider: some View {
        InspectorSlider("Width", value: frameWidth, in: 1...40, unit: .points, defaultValue: LayerStyle.default.frameWidth) { value in
            update { $0.style.frameWidth = value }
        }
        .equatable()
    }
}

/// A schematic preview of a mockup style.
private struct MockupThumbnail: View {
    let style: MockupStyle

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "8ec5fc"), Color(hex: "e0c3fc")], startPoint: .topLeading, endPoint: .bottomTrailing)
            content
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
        }
    }

    private var screen: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .none:
            screen
        case .glass:
            screen
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5))
        case .border:
            screen
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(hex: "2d2d2d")))
        case .window:
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    Circle().fill(Color(hex: "ff5f57"))
                    Circle().fill(Color(hex: "febc2e"))
                    Circle().fill(Color(hex: "28c840"))
                    Spacer()
                }
                .frame(height: 3.5)
                .padding(.horizontal, 3)
                .frame(height: 7)
                .background(Color(white: 0.2))
                Color.white
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
    }
}

// MARK: - Corners

private struct CornersSection: View, Equatable {
    let radius: Double
    let update: LayerUpdate

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.radius == rhs.radius }

    var body: some View {
        Section("Corners") {
            InspectorSlider("Radius", value: radius, in: 0...80, unit: .points, defaultValue: LayerStyle.default.cornerRadius) { value in
                update { $0.style.cornerRadius = value }
            }
            .equatable()
        }
    }
}

// MARK: - Shadow

private struct ShadowSection: View, Equatable {
    let shadow: LayerShadow
    let update: LayerUpdate

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.shadow == rhs.shadow }

    var body: some View {
        Section {
            Group {
                InspectorSlider("Blur", value: shadow.radius, in: 0...120, unit: .points, defaultValue: LayerShadow().radius) { value in
                    update { $0.style.shadow.radius = value }
                }
                .equatable()
                InspectorSlider("Opacity", value: shadow.opacity, in: 0...1, unit: .fraction, defaultValue: LayerShadow().opacity) { value in
                    update { $0.style.shadow.opacity = value }
                }
                .equatable()
                InspectorSlider("Offset", value: shadow.offsetY, in: -60...120, unit: .points, defaultValue: LayerShadow().offsetY) { value in
                    update { $0.style.shadow.offsetY = value }
                }
                .equatable()
            }
            .disabled(!shadow.isEnabled)
        } header: {
            HStack {
                Text("Shadow")
                Spacer()
                Toggle("Shadow", isOn: Binding(get: { shadow.isEnabled }, set: { isOn in update { $0.style.shadow.isEnabled = isOn } }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }
}

// MARK: - Transform

private struct TransformSection: View, Equatable {
    let scale: Double
    let rotation: Double
    let rotationX: Double
    let rotationY: Double
    let update: LayerUpdate

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.scale == rhs.scale && lhs.rotation == rhs.rotation && lhs.rotationX == rhs.rotationX && lhs.rotationY == rhs.rotationY
    }

    var body: some View {
        Section("Transform") {
            InspectorSlider("Size", value: scale, in: CanvasItem.scaleRange, unit: .percent, defaultValue: 100) { value in
                update { $0.scale = value }
            }
            .equatable()

            LabeledContent("Rotation") {
                HStack(spacing: 6) {
                    Button {
                        update { $0.rotation = Self.normalized($0.rotation - 90) }
                    } label: {
                        Label("Rotate Left", systemImage: "rotate.left")
                    }
                    .help("Rotate 90° left")

                    Text(SliderUnit.degrees.format(rotation))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36)

                    Button {
                        update { $0.rotation = Self.normalized($0.rotation + 90) }
                    } label: {
                        Label("Rotate Right", systemImage: "rotate.right")
                    }
                    .help("Rotate 90° right")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }

            InspectorSlider("Vertical tilt", value: rotationX, in: -60...60, unit: .degrees, defaultValue: 0) { value in
                update { $0.rotationX = value }
            }
            .equatable()
            InspectorSlider("Horizontal tilt", value: rotationY, in: -60...60, unit: .degrees, defaultValue: 0) { value in
                update { $0.rotationY = value }
            }
            .equatable()

            Button("Reset Transform") {
                update { item in
                    item.scale = 100
                    item.rotation = 0
                    item.rotationX = 0
                    item.rotationY = 0
                }
            }
            .disabled(scale == 100 && rotation == 0 && rotationX == 0 && rotationY == 0)
        }
    }

    /// Keeps the angle in -180…180.
    private static func normalized(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }
}
