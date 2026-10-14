import SwiftUI

/// The Background page: background kind, its options, and background effects.
///
/// Each part is an `Equatable` view fed with plain values, so dragging a slider only redraws
/// that slider (not the wallpaper grid, the swatches or the other sliders).
struct BackgroundInspector: View {
    let model: ScreenshotEditorViewModel

    var body: some View {
        let config = model.config
        Section("Background") {
            BackgroundTypePicker(type: config.backgroundType) { model.config.backgroundType = $0 }
                .equatable()

            switch config.backgroundType {
            case .transparent:
                Text("The image keeps a transparent background. JPEG files use white instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .color:
                ColorOptions(selection: config.backgroundColor) { color in
                    model.selectBackgroundColor(color)
                }
                .equatable()
            case .gradient:
                GradientOptions(
                    gradient: config.gradient,
                    onSelect: { model.selectGradient($0) },
                    update: { change in change(&model.config.gradient) },
                    onRandomize: { model.randomizeGradient() }
                )
                .equatable()
            case .image:
                WallpaperGrid(
                    library: model.wallpapers,
                    selection: config.backgroundImage,
                    onSelect: { model.selectWallpaper($0) }
                )
                .equatable()

                Button {
                    model.importBackgroundImage()
                } label: {
                    Label("Choose Image…", systemImage: "photo.badge.plus")
                }
            }
        }

        if config.backgroundType != .transparent {
            EffectsSection(effects: config.effects) { change in change(&model.config.effects) }
                .equatable()
        }
    }
}

// MARK: - Type

private struct BackgroundTypePicker: View, Equatable {
    let type: BackgroundType
    let onChange: (BackgroundType) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.type == rhs.type }

    var body: some View {
        Picker("Background", selection: Binding(get: { type }, set: onChange)) {
            ForEach(BackgroundType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - Color

private struct ColorOptions: View, Equatable {
    let selection: RGBAColor
    let onSelect: (RGBAColor) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.selection == rhs.selection }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 34), spacing: 6)], spacing: 6) {
            ForEach(ColorSwatch.colors, id: \.self) { color in
                ColorSwatchButton(color: color, isSelected: selection == color) {
                    onSelect(color)
                }
            }
        }
        ColorPicker(
            "Custom Color",
            selection: Binding(get: { selection.color }, set: { onSelect(RGBAColor($0)) }),
            supportsOpacity: false
        )
    }
}

// MARK: - Gradient

private struct GradientOptions: View, Equatable {
    let gradient: GradientFill
    /// Picks a preset.
    let onSelect: (GradientFill) -> Void
    /// Edits the current gradient in place (on the model's value, never on a stale copy).
    let update: ((inout GradientFill) -> Void) -> Void
    let onRandomize: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.gradient == rhs.gradient }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
            ForEach(GradientPreset.presets) { preset in
                SelectableTile(title: Text(preset.name), isSelected: gradient == preset.fill) {
                    onSelect(preset.fill)
                } content: {
                    preset.fill.view(size: CGSize(width: 44, height: 30))
                        .frame(height: 30)
                }
            }
        }

        Picker("Style", selection: Binding(get: { gradient.style }, set: { style in update { $0.style = style } })) {
            ForEach(GradientStyle.allCases) { style in
                Text(style.displayName).tag(style)
            }
        }
        .pickerStyle(.segmented)

        LabeledContent("Colors") {
            HStack(spacing: 6) {
                ForEach(gradient.colors.indices, id: \.self) { index in
                    ColorPicker("Color \(index + 1)", selection: color(at: index), supportsOpacity: false)
                        .labelsHidden()
                }
                Button {
                    update(Self.toggleMiddleColor)
                } label: {
                    Label(
                        gradient.colors.count == 3 ? "Remove Middle Color" : "Add Middle Color",
                        systemImage: gradient.colors.count == 3 ? "minus.circle" : "plus.circle"
                    )
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(gradient.colors.count == 3 ? "Remove Middle Color" : "Add Middle Color")
            }
        }

        if gradient.style == .linear {
            InspectorSlider("Angle", value: gradient.angle, in: 0...360, step: 5, unit: .degrees, defaultValue: 135) { angle in
                update { $0.angle = angle }
            }
            .equatable()
        }

        Button {
            onRandomize()
        } label: {
            Label("Random Gradient", systemImage: "dice")
        }
    }

    /// A gradient stop's color. Bounds-checked: the color panel may still write to a stop
    /// that "Remove Middle Color" just deleted.
    private func color(at index: Int) -> Binding<Color> {
        Binding(
            get: { gradient.colors.indices.contains(index) ? gradient.colors[index].color : .clear },
            set: { newValue in
                update { gradient in
                    guard gradient.colors.indices.contains(index) else { return }
                    gradient.colors[index] = RGBAColor(newValue)
                }
            }
        )
    }

    nonisolated private static func toggleMiddleColor(_ gradient: inout GradientFill) {
        if gradient.colors.count == 3 {
            gradient.colors.remove(at: 1)
        } else if gradient.colors.count == 2 {
            gradient.colors.insert(gradient.colors[0].mixed(with: gradient.colors[1]), at: 1)
        }
    }
}

nonisolated private extension RGBAColor {
    func mixed(with other: RGBAColor) -> RGBAColor {
        RGBAColor(red: (red + other.red) / 2, green: (green + other.green) / 2, blue: (blue + other.blue) / 2, alpha: (alpha + other.alpha) / 2)
    }
}

// MARK: - Image

/// The wallpaper grid. It depends only on the selection and on the library (entries and
/// thumbnails, observed directly), so canvas edits never redraw its tiles.
private struct WallpaperGrid: View, Equatable {
    let library: WallpaperLibrary
    let selection: BackgroundImageSource
    let onSelect: (BackgroundImageSource) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.library === rhs.library && lhs.selection == rhs.selection
    }

    var body: some View {
        if library.entries.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading wallpapers…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 6)], spacing: 6) {
                ForEach(library.entries) { entry in
                    SelectableTile(title: Text(entry.name), isSelected: selection == entry.source) {
                        onSelect(entry.source)
                    } content: {
                        ZStack {
                            Rectangle().fill(.quaternary)
                            if let thumbnail = library.thumbnails[entry.source] {
                                Image(decorative: thumbnail, scale: 1)
                                    .resizable()
                                    .interpolation(.medium)
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(height: 38)
                        .clipped()
                    }
                }
            }
        }
    }
}

// MARK: - Effects

private struct EffectsSection: View, Equatable {
    let effects: BackgroundEffects
    /// Edits the model's effects in place.
    let update: ((inout BackgroundEffects) -> Void) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.effects == rhs.effects }

    var body: some View {
        Section("Effects") {
            InspectorSlider("Blur", value: effects.blur, in: 0...80, unit: .points, defaultValue: 0) { value in
                update { $0.blur = value }
            }
            .equatable()
            InspectorSlider("Grain", value: effects.grain, in: 0...100, unit: .percent, defaultValue: 0) { value in
                update { $0.grain = value }
            }
            .equatable()
            InspectorSlider("Saturation", value: effects.saturation, in: 0...200, unit: .percent, defaultValue: 100) { value in
                update { $0.saturation = value }
            }
            .equatable()
            InspectorSlider("Brightness", value: effects.brightness, in: 50...150, unit: .percent, defaultValue: 100) { value in
                update { $0.brightness = value }
            }
            .equatable()

            Button("Reset Effects") {
                update { $0 = BackgroundEffects() }
            }
            .disabled(effects.isDefault)
        }
    }
}
