import SwiftUI

/// The Canvas page: canvas size presets, padding, export format and style reset.
struct CanvasInspector: View {
    @Bindable var model: ScreenshotEditorViewModel

    var body: some View {
        Section("Size") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 8) {
                SizeTile(preset: nil, isSelected: model.config.canvasPresetID == nil) {
                    model.config.canvasPresetID = nil
                }
                ForEach(SocialMediaPreset.presets) { preset in
                    SizeTile(preset: preset, isSelected: model.config.canvasPresetID == preset.id) {
                        model.config.canvasPresetID = preset.id
                    }
                }
            }
        }

        Section("Layout") {
            InspectorSlider("Padding", value: $model.config.padding, in: 0...400, unit: .points, defaultValue: ScreenshotStyleConfig.default.padding)
            LabeledContent("Position") {
                Button("Center Layers") {
                    model.centerLayers()
                }
                .help("Move the screenshots to the middle of the canvas.")
            }
        }

        Section("Export") {
            Picker("Format", selection: $model.exportFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)

            if model.exportFormat == .jpeg {
                InspectorSlider("Quality", value: $model.jpegQuality, in: 0.3...1, unit: .fraction, defaultValue: 0.9)
            }

            LabeledContent("Image Size") {
                Text(model.geometry.pixelSizeDescription)
                    .monospacedDigit()
            }
        }

        Section {
            Button("Reset Style") {
                model.resetStyle()
            }
        } footer: {
            Text("New screenshots open with the style you used last. Reset Style restores the default background, frame, corners and shadow.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Size Tile

/// A canvas size choice, drawn with the preset's aspect ratio.
private struct SizeTile: View {
    let preset: SocialMediaPreset?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            SelectableTile(title: description, isSelected: isSelected, action: action) {
                ZStack {
                    Rectangle().fill(.quinary)
                    shape
                }
                .frame(height: 40)
            }
            .padding(.bottom, 2)

            Group {
                if let preset {
                    Text(verbatim: preset.name)
                } else {
                    Text("Auto")
                }
            }
            .font(.caption)
            .foregroundStyle(isSelected ? .primary : .secondary)

            Group {
                if let preset {
                    Text(verbatim: preset.platform)
                } else {
                    Text("Fit Image")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
    }

    private var description: Text {
        guard let preset else { return Text("Auto: fits the screenshot, at full resolution") }
        return Text(verbatim: "\(preset.platform) \(preset.name), \(preset.width) × \(preset.height) px")
    }

    @ViewBuilder
    private var shape: some View {
        if let preset {
            let box = CGSize(width: 34, height: 26)
            let fit = min(box.width / CGFloat(preset.width), box.height / CGFloat(preset.height))
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary, lineWidth: 1.5)
                .frame(width: CGFloat(preset.width) * fit, height: CGFloat(preset.height) * fit)
        } else {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
    }
}
