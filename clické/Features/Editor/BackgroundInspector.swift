import SwiftUI

/// The Background page: background kind, its options, and background effects.
struct BackgroundInspector: View {
    @Bindable var model: ScreenshotEditorViewModel

    var body: some View {
        Section("Background") {
            Picker("Background", selection: $model.config.backgroundType) {
                ForEach(BackgroundType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.config.backgroundType {
            case .transparent:
                Text("The image keeps a transparent background. JPEG files use white instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .color:
                ColorOptions(model: model)
            case .gradient:
                GradientOptions(model: model)
            case .image:
                WallpaperOptions(model: model)
            }
        }

        if model.config.backgroundType != .transparent {
            EffectsSection(model: model)
        }
    }
}

// MARK: - Color

private struct ColorOptions: View {
    @Bindable var model: ScreenshotEditorViewModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 34), spacing: 6)], spacing: 6) {
            ForEach(ColorSwatch.colors, id: \.self) { color in
                ColorSwatchButton(color: color, isSelected: model.config.backgroundColor == color) {
                    model.selectBackgroundColor(color)
                }
            }
        }
        ColorPicker("Custom Color", selection: $model.config.backgroundColor.color, supportsOpacity: false)
    }
}

// MARK: - Gradient

private struct GradientOptions: View {
    @Bindable var model: ScreenshotEditorViewModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
            ForEach(GradientPreset.presets) { preset in
                SelectableTile(title: Text(preset.name), isSelected: model.config.gradient == preset.fill) {
                    model.selectGradient(preset.fill)
                } content: {
                    preset.fill.view(size: CGSize(width: 44, height: 30))
                        .frame(height: 30)
                }
            }
        }

        Picker("Style", selection: $model.config.gradient.style) {
            ForEach(GradientStyle.allCases) { style in
                Text(style.displayName).tag(style)
            }
        }
        .pickerStyle(.segmented)

        LabeledContent("Colors") {
            HStack(spacing: 6) {
                ForEach(model.config.gradient.colors.indices, id: \.self) { index in
                    ColorPicker("Color \(index + 1)", selection: $model.config.gradient.colors[index].color, supportsOpacity: false)
                        .labelsHidden()
                }
                Button {
                    toggleThirdColor()
                } label: {
                    Label(
                        model.config.gradient.colors.count == 3 ? "Remove Middle Color" : "Add Middle Color",
                        systemImage: model.config.gradient.colors.count == 3 ? "minus.circle" : "plus.circle"
                    )
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(model.config.gradient.colors.count == 3 ? "Remove Middle Color" : "Add Middle Color")
            }
        }

        if model.config.gradient.style == .linear {
            InspectorSlider("Angle", value: $model.config.gradient.angle, in: 0...360, step: 5, unit: .degrees, defaultValue: 135)
        }

        Button {
            model.randomizeGradient()
        } label: {
            Label("Random Gradient", systemImage: "dice")
        }
    }

    private func toggleThirdColor() {
        var colors = model.config.gradient.colors
        if colors.count == 3 {
            colors.remove(at: 1)
        } else if colors.count == 2 {
            colors.insert(colors[0].mixed(with: colors[1]), at: 1)
        }
        model.config.gradient.colors = colors
    }
}

private extension RGBAColor {
    func mixed(with other: RGBAColor) -> RGBAColor {
        RGBAColor(red: (red + other.red) / 2, green: (green + other.green) / 2, blue: (blue + other.blue) / 2, alpha: (alpha + other.alpha) / 2)
    }
}

// MARK: - Image

private struct WallpaperOptions: View {
    let model: ScreenshotEditorViewModel

    var body: some View {
        let library = model.wallpapers
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
                    SelectableTile(title: Text(entry.name), isSelected: model.config.backgroundImage == entry.source) {
                        model.selectWallpaper(entry.source)
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

        Button {
            model.importBackgroundImage()
        } label: {
            Label("Choose Image…", systemImage: "photo.badge.plus")
        }
    }
}

// MARK: - Effects

private struct EffectsSection: View {
    @Bindable var model: ScreenshotEditorViewModel

    var body: some View {
        Section("Effects") {
            InspectorSlider("Blur", value: $model.config.effects.blur, in: 0...80, unit: .points, defaultValue: 0)
            InspectorSlider("Grain", value: $model.config.effects.grain, in: 0...100, unit: .percent, defaultValue: 0)
            InspectorSlider("Saturation", value: $model.config.effects.saturation, in: 0...200, unit: .percent, defaultValue: 100)
            InspectorSlider("Brightness", value: $model.config.effects.brightness, in: 50...150, unit: .percent, defaultValue: 100)

            Button("Reset Effects") {
                model.config.effects = BackgroundEffects()
            }
            .disabled(model.config.effects.isDefault)
        }
    }
}
