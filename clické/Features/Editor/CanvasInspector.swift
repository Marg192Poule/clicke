import SwiftUI

/// The Canvas page: canvas size presets, padding, export format and style reset.
///
/// The parts are `Equatable` views fed with plain values, so dragging the padding slider only
/// redraws that slider and the image size.
struct CanvasInspector: View {
    let model: ScreenshotEditorViewModel

    var body: some View {
        SizeSection(selectedPresetID: model.config.canvasPresetID) { model.config.canvasPresetID = $0 }
            .equatable()

        Section("Layout") {
            InspectorSlider("Padding", value: model.config.padding, in: 0...400, unit: .points, defaultValue: ScreenshotStyleConfig.default.padding) {
                model.config.padding = $0
            }
            .equatable()
            LabeledContent("Position") {
                Button("Center Layers") {
                    model.centerLayers()
                }
                .help("Move the screenshots to the middle of the canvas.")
            }
        }

        ExportSection(
            format: model.exportFormat,
            jpegQuality: model.jpegQuality,
            pixelSizeDescription: model.geometry.pixelSizeDescription,
            onFormatChange: { model.exportFormat = $0 },
            onQualityChange: { model.jpegQuality = $0 }
        )
        .equatable()

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

// MARK: - Size

/// The canvas size grid; it only redraws when the selected size changes.
private struct SizeSection: View, Equatable {
    let selectedPresetID: String?
    let onSelect: (String?) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.selectedPresetID == rhs.selectedPresetID }

    var body: some View {
        Section("Size") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 8) {
                SizeTile(preset: nil, isSelected: selectedPresetID == nil) {
                    onSelect(nil)
                }
                ForEach(SocialMediaPreset.presets) { preset in
                    SizeTile(preset: preset, isSelected: selectedPresetID == preset.id) {
                        onSelect(preset.id)
                    }
                }
            }
        }
    }
}

// MARK: - Export

private struct ExportSection: View, Equatable {
    let format: ExportFormat
    let jpegQuality: Double
    let pixelSizeDescription: String
    let onFormatChange: (ExportFormat) -> Void
    let onQualityChange: (Double) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.format == rhs.format && lhs.jpegQuality == rhs.jpegQuality && lhs.pixelSizeDescription == rhs.pixelSizeDescription
    }

    var body: some View {
        Section("Export") {
            Picker("Format", selection: Binding(get: { format }, set: onFormatChange)) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)

            if format == .jpeg {
                InspectorSlider("Quality", value: jpegQuality, in: 0.3...1, unit: .fraction, defaultValue: 0.9, onChange: onQualityChange)
                    .equatable()
            }

            LabeledContent("Image Size") {
                Text(pixelSizeDescription)
                    .monospacedDigit()
            }
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
