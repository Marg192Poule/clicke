import SwiftUI
import AppKit

/// Sheet that lets the user hide sensitive parts of a screenshot (blur, pixelate, solid bar).
///
/// Contract used by the editor:
/// - `image`: the screenshot to redact (shown flat, without any styling/transform).
/// - `onApply`: called with the redacted image (same point size and pixel size as the input).
/// - `onCancel`: called when the user dismisses without applying.
struct RedactionEditorView: View {
    let image: NSImage
    let onApply: (NSImage) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(minWidth: 480, minHeight: 320)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { onApply(image) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
