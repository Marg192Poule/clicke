import SwiftUI

/// The Style page: layers, then the selected layer's frame, corners, shadow and transform.
struct StyleInspector: View {
    @Bindable var model: ScreenshotEditorViewModel

    var body: some View {
        if model.items.count > 1 {
            LayersSection(model: model)
        }

        if let id = model.selectedItemID, let item = model.binding(forItem: id) {
            FrameSection(item: item)
            CornersSection(item: item)
            ShadowSection(item: item)
            TransformSection(item: item)
        } else {
            Section {
                ContentUnavailableView(
                    "No Layer Selected",
                    systemImage: "cursorarrow.click",
                    description: Text("Click a screenshot on the canvas to edit its style.")
                )
            }
        }
    }
}

// MARK: - Layers

private struct LayersSection: View {
    let model: ScreenshotEditorViewModel

    var body: some View {
        Section("Layers") {
            ForEach(model.items.sorted { $0.zIndex > $1.zIndex }) { item in
                let isSelected = model.selectedItemID == item.id
                Button {
                    model.selectedItemID = item.id
                } label: {
                    HStack(spacing: 10) {
                        Image(decorative: item.image.preview ?? item.image.cgImage, scale: 1)
                            .resizable()
                            .interpolation(.medium)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        Text(layerName(for: item))
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
                    Button("Bring to Front") {
                        model.selectedItemID = item.id
                        model.bringSelectedToFront()
                    }
                    Button("Send to Back") {
                        model.selectedItemID = item.id
                        model.sendSelectedToBack()
                    }
                    Divider()
                    Button("Delete Layer", role: .destructive) {
                        model.selectedItemID = item.id
                        model.removeSelectedItem()
                    }
                }
            }

            HStack {
                ControlGroup {
                    Button {
                        model.bringSelectedToFront()
                    } label: {
                        Label("Bring to Front", systemImage: "square.3.layers.3d.top.filled")
                    }
                    .help("Bring to Front")
                    Button {
                        model.sendSelectedToBack()
                    } label: {
                        Label("Send to Back", systemImage: "square.3.layers.3d.bottom.filled")
                    }
                    .help("Send to Back")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
                .disabled(model.selectedItemID == nil)

                Spacer()

                Button("Apply Style to All") {
                    model.applySelectedStyleToAllLayers()
                }
                .disabled(model.selectedItemID == nil)
                .help("Give every layer the frame, corners and shadow of the selected one.")

                Button(role: .destructive) {
                    model.removeSelectedItem()
                } label: {
                    Label("Delete Layer", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Delete Layer (⌫)")
                .disabled(model.selectedItemID == nil)
            }
        }
    }

    private func layerName(for item: CanvasItem) -> String {
        let number = (model.items.firstIndex { $0.id == item.id } ?? 0) + 1
        return String(localized: "Layer \(number)")
    }
}

// MARK: - Frame

private struct FrameSection: View {
    @Binding var item: CanvasItem

    var body: some View {
        Section("Frame") {
            HStack(spacing: 8) {
                ForEach(MockupStyle.allCases) { style in
                    CaptionedTile(title: Text(style.displayName), isSelected: item.style.mockup == style) {
                        item.style.mockup = style
                    } content: {
                        MockupThumbnail(style: style)
                            .frame(height: 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            switch item.style.mockup {
            case .none:
                EmptyView()
            case .glass:
                InspectorSlider("Width", value: $item.style.frameWidth, in: 1...40, unit: .points, defaultValue: LayerStyle.default.frameWidth)
            case .border:
                InspectorSlider("Width", value: $item.style.frameWidth, in: 1...40, unit: .points, defaultValue: LayerStyle.default.frameWidth)
                ColorPicker("Color", selection: $item.style.borderColor.color, supportsOpacity: false)
            case .window:
                Picker("Title Bar", selection: $item.style.windowAppearance) {
                    ForEach(WindowChromeAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
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

private struct CornersSection: View {
    @Binding var item: CanvasItem

    var body: some View {
        Section("Corners") {
            InspectorSlider("Radius", value: $item.style.cornerRadius, in: 0...80, unit: .points, defaultValue: LayerStyle.default.cornerRadius)
        }
    }
}

// MARK: - Shadow

private struct ShadowSection: View {
    @Binding var item: CanvasItem

    var body: some View {
        Section {
            Group {
                InspectorSlider("Blur", value: $item.style.shadow.radius, in: 0...120, unit: .points, defaultValue: LayerShadow().radius)
                InspectorSlider("Opacity", value: $item.style.shadow.opacity, in: 0...1, unit: .fraction, defaultValue: LayerShadow().opacity)
                InspectorSlider("Offset", value: $item.style.shadow.offsetY, in: -60...120, unit: .points, defaultValue: LayerShadow().offsetY)
            }
            .disabled(!item.style.shadow.isEnabled)
        } header: {
            HStack {
                Text("Shadow")
                Spacer()
                Toggle("Shadow", isOn: $item.style.shadow.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }
}

// MARK: - Transform

private struct TransformSection: View {
    @Binding var item: CanvasItem

    var body: some View {
        Section("Transform") {
            InspectorSlider("Size", value: $item.scale, in: CanvasItem.scaleRange, unit: .percent, defaultValue: 100)

            LabeledContent("Rotation") {
                HStack(spacing: 6) {
                    Button {
                        item.rotation = normalized(item.rotation - 90)
                    } label: {
                        Label("Rotate Left", systemImage: "rotate.left")
                    }
                    .help("Rotate Left")

                    Text(SliderUnit.degrees.format(item.rotation))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36)

                    Button {
                        item.rotation = normalized(item.rotation + 90)
                    } label: {
                        Label("Rotate Right", systemImage: "rotate.right")
                    }
                    .help("Rotate Right")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }

            InspectorSlider("Vertical Tilt", value: $item.rotationX, in: -60...60, unit: .degrees, defaultValue: 0)
            InspectorSlider("Horizontal Tilt", value: $item.rotationY, in: -60...60, unit: .degrees, defaultValue: 0)

            Button("Reset Transform") {
                item.scale = 100
                item.rotation = 0
                item.rotationX = 0
                item.rotationY = 0
            }
            .disabled(item.scale == 100 && item.rotation == 0 && item.rotationX == 0 && item.rotationY == 0)
        }
    }

    /// Keeps the angle in -180…180.
    private func normalized(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }
}
