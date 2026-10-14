import AppKit
import SwiftUI

/// Sheet that lets the user hide sensitive parts of a screenshot (pixelate, blur, solid fill).
///
/// Contract used by the editor:
/// - `image`: the screenshot to redact (shown flat, without any styling/transform).
/// - `onApply`: called with the redacted image (same point size and pixel size as the input),
///   with the redaction baked into the pixels.
/// - `onCancel`: called when the user dismisses without applying.
struct RedactionEditorView: View {
    let image: NSImage
    let onApply: (NSImage) -> Void
    let onCancel: () -> Void

    @State private var model: RedactionEditorModel
    /// Narrow sheets collapse some header labels so every control stays visible.
    @State private var isCompact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(image: NSImage, onApply: @escaping (NSImage) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.onApply = onApply
        self.onCancel = onCancel
        _model = State(initialValue: RedactionEditorModel(image: image))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            RedactionCanvasView(model: model)
                .background(Color(nsColor: .underPageBackgroundColor))
                .overlay(alignment: .top) { statusBanner }
            Divider()
            footer
        }
        .frame(
            minWidth: 640,
            idealWidth: Self.idealSize.width,
            minHeight: 440,
            idealHeight: Self.idealSize.height
        )
        // Open at the ideal size rather than the minimum.
        .presentationSizing(.fitted)
        .onGeometryChange(for: Bool.self) { $0.size.width < 860 } action: { isCompact = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.status)
        .task { await model.prepare() }
        .onDisappear { model.cancelTasks() }
        .onChange(of: model.status) { _, status in
            if let status {
                AccessibilityNotification.Announcement(status.message).post()
            }
        }
    }

    /// About 80% of the screen's visible area.
    private static var idealSize: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(
            width: max(640, (visible.width * 0.8).rounded()),
            height: max(440, (visible.height * 0.8).rounded())
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            Picker("Style", selection: styleBinding) {
                ForEach(RedactionStyle.allCases) { style in
                    Label {
                        Text(style.title)
                    } icon: {
                        Image(systemName: style.systemImage)
                    }
                    .tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Style for new areas and the selected area")

            styleOptions
                .frame(width: isCompact ? 96 : 180, alignment: .leading)

            Spacer(minLength: 8)

            if model.isDetecting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Finding sensitive text")
            }

            Button {
                model.findSensitiveText()
            } label: {
                if isCompact {
                    Label("Find Sensitive Text", systemImage: "text.viewfinder")
                        .labelStyle(.iconOnly)
                } else {
                    Label("Find Sensitive Text", systemImage: "text.viewfinder")
                }
            }
            .disabled(model.isDetecting)
            .help("Find and hide email addresses, phone numbers, card numbers, keys, and other sensitive text. Text is recognized on this Mac.")

            Divider()
                .frame(height: 18)

            editButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .disabled(!model.canEdit || model.isApplying)
    }

    /// Strength for pixelate and blur, color for solid. Both share one slot so the header doesn't jump.
    @ViewBuilder
    private var styleOptions: some View {
        if model.settings.style.usesStrength {
            Slider(value: strengthBinding, in: 0...1) {
                Text("Strength")
            } onEditingChanged: { isEditing in
                if isEditing {
                    model.beginChange()
                } else {
                    model.endChange()
                }
            }
            .labelsVisibility(isCompact ? .hidden : .automatic)
            .accessibilityValue(Text(model.settings.strength, format: .percent.precision(.fractionLength(0))))
            .help("How strongly the area is obscured")
        } else {
            Picker("Color", selection: fillBinding) {
                ForEach(RedactionFill.allCases) { fill in
                    Label {
                        Text(fill.title)
                    } icon: {
                        Image(nsImage: Self.swatch(for: fill))
                    }
                    .tag(fill)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Fill color")
        }
    }

    private var editButtons: some View {
        HStack(spacing: 8) {
            Button {
                model.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!model.canUndo)
            .help("Undo")

            Button {
                model.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.canRedo)
            .help("Redo")

            Button {
                model.deleteSelection()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(model.selectedID == nil)
            .help("Delete the selected area (⌫)")

            Button("Clear All") {
                model.clearAll()
            }
            .disabled(model.regions.isEmpty)
            .help("Remove all hidden areas")
        }
        .labelStyle(.iconOnly)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Label("Blurred or pixelated text can sometimes be recovered. For passwords and keys, use Solid.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            if model.isApplying {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Applying")
            }

            Button("Cancel", role: .cancel) {
                model.cancelTasks()
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button("Apply") {
                apply()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canEdit || model.isApplying)
            .help("Permanently hide the selected areas in the screenshot")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusBanner: some View {
        if let status = model.status {
            Label {
                Text(status.message)
            } icon: {
                Image(systemName: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(status.isError ? Color.orange : Color.green)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .padding(.top, 12)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Actions

    private func apply() {
        Task {
            guard let result = await model.renderResult() else { return }
            onApply(result)
        }
    }

    // MARK: - Bindings

    private var styleBinding: Binding<RedactionStyle> {
        Binding(get: { model.settings.style }, set: { model.setStyle($0) })
    }

    private var strengthBinding: Binding<Double> {
        Binding(get: { model.settings.strength }, set: { model.setStrength($0) })
    }

    private var fillBinding: Binding<RedactionFill> {
        Binding(get: { model.settings.fill }, set: { model.setFill($0) })
    }

    // MARK: - Helpers

    /// A colored circle for the fill menu. Not a template, so menus keep its color.
    private static func swatch(for fill: RedactionFill) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            NSColor(srgbRed: fill.whiteLevel, green: fill.whiteLevel, blue: fill.whiteLevel, alpha: 1).setFill()
            circle.fill()
            NSColor.tertiaryLabelColor.setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
