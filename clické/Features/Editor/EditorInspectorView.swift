import SwiftUI

/// The right-hand inspector: Style (selected layer), Background and Canvas pages,
/// with a drag-to-export thumbnail at the bottom.
struct EditorInspectorView: View {
    @Bindable var model: ScreenshotEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector Page", selection: $model.inspectorTab) {
                Text("Style").tag(InspectorTab.style)
                Text("Background").tag(InspectorTab.background)
                Text("Canvas").tag(InspectorTab.canvas)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)

            Form {
                switch model.inspectorTab {
                case .style:
                    StyleInspector(model: model)
                case .background:
                    BackgroundInspector(model: model)
                case .canvas:
                    CanvasInspector(model: model)
                }
            }
            .formStyle(.grouped)

            ExportFooter(model: model)
        }
    }
}

// MARK: - Export Footer

/// A thumbnail of the result that can be dragged into Finder, Mail, Slack…
private struct ExportFooter: View {
    let model: ScreenshotEditorViewModel

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                thumbnail
                    .frame(width: 76, height: 52)
                    .onDrag {
                        model.dragItemProvider()
                    } preview: {
                        thumbnail.frame(width: 160, height: 110)
                    }
                    .onHover { isHovering = $0 }
                    .pointerStyle(.grabIdle)
                    .help("Drag the image to Finder, Mail, Messages or any other app.")
                    .accessibilityLabel("Exported image")
                    .accessibilityHint("Drag to export the image to another app.")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Drag to Export")
                        .font(.callout.weight(.medium))
                    Text("\(model.geometry.pixelSizeDescription) · \(model.exportFormat.displayName)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var thumbnail: some View {
        ZStack {
            if let image = model.exportThumbnail {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(isHovering ? 0.3 : 0.18), radius: isHovering ? 4 : 2, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.quaternary)
            }
        }
    }
}

// MARK: - Save Panel Accessory

/// Format options shown in the save panel (the same setting as the Canvas page).
struct SaveFormatAccessory: View {
    @Bindable var model: ScreenshotEditorViewModel
    let onFormatChange: (ExportFormat) -> Void

    var body: some View {
        // The quality slider stays in place (disabled for PNG) so the panel doesn't jump.
        HStack(spacing: 16) {
            Picker("Format:", selection: $model.exportFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .fixedSize()

            HStack(spacing: 6) {
                Text("Quality:")
                Slider(value: $model.jpegQuality, in: 0.3...1)
                    .frame(width: 120)
                    .accessibilityLabel("Quality")
                Text(SliderUnit.fraction.format(model.jpegQuality))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .disabled(model.exportFormat != .jpeg)
        }
        .fixedSize()
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .onChange(of: model.exportFormat) { _, format in
            onFormatChange(format)
        }
    }
}
