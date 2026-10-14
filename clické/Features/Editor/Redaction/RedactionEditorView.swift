import AppKit
import SwiftUI

/// Sheet that lets the user hide sensitive parts of a screenshot (pixelate, blur, solid fill).
///
/// Contract used by the editor:
/// - `image`: the screenshot to redact (shown flat, without any styling/transform).
/// - `onApply`: called with the redacted image, with the redaction baked into the pixels. Its
///   only representation is an `NSBitmapImageRep` with the input's pixel size and color space,
///   and the image has the input's point size. Not called when there is nothing to hide.
/// - `onCancel`: called when the sheet closes without changing the image.
struct RedactionEditorView: View {
    let image: NSImage
    let onApply: (NSImage) -> Void
    let onCancel: () -> Void

    @State private var model: RedactionEditorModel
    /// Size the sheet opens at, fixed when it opens.
    @State private var idealSize: CGSize
    /// Narrow sheets collapse some header labels so every control stays visible.
    @State private var isCompact = false
    @State private var isConfirmingDiscard = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(image: NSImage, onApply: @escaping (NSImage) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.onApply = onApply
        self.onCancel = onCancel
        _model = State(initialValue: RedactionEditorModel(image: image))
        _idealSize = State(initialValue: Self.preferredSize())
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
        // On the whole sheet, so Esc reaches it wherever the focus is.
        .onExitCommand(perform: handleEscape)
        .frame(
            minWidth: 640,
            idealWidth: idealSize.width,
            minHeight: 440,
            idealHeight: idealSize.height
        )
        // Open at the ideal size rather than the minimum.
        .presentationSizing(.fitted)
        // Every way out goes through Cancel or Apply, so marked areas are never lost silently.
        .interactiveDismissDisabled()
        .onGeometryChange(for: Bool.self) { $0.size.width < 860 } action: { isCompact = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.status)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.showsHint)
        .task { await model.prepare() }
        .onDisappear { model.close() }
        .onChange(of: model.status) { _, status in
            if let status {
                AccessibilityNotification.Announcement(status.message).post()
            }
        }
        .confirmationDialog("Discard Redactions?", isPresented: $isConfirmingDiscard) {
            Button("Discard", role: .destructive) {
                discard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The areas you marked won’t be applied.")
        }
    }

    /// The content area of the window the sheet opens on, minus a margin, so the sheet fits
    /// inside it. Falls back to most of the screen under the pointer.
    private static func preferredSize() -> CGSize {
        let available: CGSize
        if let window = NSApp.keyWindow.map({ $0.sheetParent ?? $0 }) {
            let content = window.contentLayoutRect.size
            available = CGSize(width: content.width - 40, height: content.height - 40)
        } else {
            let visible = ScreenLocator.screenUnderPointer()?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
            available = CGSize(width: visible.width * 0.8, height: visible.height * 0.8)
        }
        return CGSize(
            width: max(640, available.width.rounded()),
            height: max(440, available.height.rounded())
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
            .help("Undo (⌘Z)")

            Button {
                model.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.canRedo)
            .help("Redo (⇧⌘Z)")

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
            .help("Remove all marked areas")
        }
        .labelStyle(.iconOnly)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Label("Blurred or pixelated text can sometimes be recovered. For passwords and keys, use Solid.", systemImage: "info.circle")
                .font(.callout)
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
                requestCancel()
            }
            // While an area is selected, Esc deselects it instead (see `handleEscape()`).
            .keyboardShortcut(model.selectedID == nil || model.isApplying ? .cancelAction : nil)

            Button("Apply") {
                apply()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canApply)
            .help("Hide all marked areas in the image")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusBanner: some View {
        if let status = model.status {
            banner {
                Label {
                    Text(status.message)
                } icon: {
                    Image(systemName: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(status.isError ? Color.orange : Color.green)
                }
            }
        } else if model.showsHint {
            banner {
                Text("Drag over the image to hide an area, or click Find Sensitive Text.")
            }
        }
    }

    private func banner(@ViewBuilder content: () -> some View) -> some View {
        content()
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 12)
            .padding(.horizontal, 16)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func apply() {
        model.apply { result in
            model.close()
            if let result {
                onApply(result)
            } else {
                // Nothing to hide: leave the image as it is.
                onCancel()
            }
        }
    }

    /// Cancel button: asks before throwing away marked areas.
    private func requestCancel() {
        // Stop a render in progress first, so its result can't be applied after all.
        model.cancelApply()
        if model.hasUnappliedChanges {
            isConfirmingDiscard = true
        } else {
            discard()
        }
    }

    /// Esc: deselects the selected area first, then cancels like the Cancel button.
    private func handleEscape() {
        if model.selectedID != nil, !model.isApplying {
            model.select(nil)
        } else {
            requestCancel()
        }
    }

    private func discard() {
        model.close()
        onCancel()
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
