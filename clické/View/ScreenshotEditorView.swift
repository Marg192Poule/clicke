import SwiftUI
import AppKit

/// The screenshot editor: canvas, inspector and redaction sheet (the toolbar is `EditorToolbarController`).
struct ScreenshotEditorView: View {
    @Bindable var model: ScreenshotEditorViewModel

    var body: some View {
        ScreenshotPreviewCanvas(model: model)
            .frame(minWidth: 420, minHeight: 360)
            .inspector(isPresented: $model.isInspectorPresented) {
                EditorInspectorView(model: model)
                    .inspectorColumnWidth(min: 290, ideal: 320, max: 420)
            }
            .sheet(item: $model.redactionRequest) { request in
                RedactionEditorView(
                    image: request.image,
                    onApply: { redacted in
                        model.applyRedaction(redacted, toItem: request.itemID)
                    },
                    onCancel: {
                        model.redactionRequest = nil
                    }
                )
            }
            .environment(\.editorInteraction, EditorInteraction(begin: model.beginInteraction, end: model.endInteraction))
            .task {
                // After the first frame: the wallpaper grid isn't needed to show the editor.
                model.wallpapers.loadIfNeeded()
            }
    }
}
