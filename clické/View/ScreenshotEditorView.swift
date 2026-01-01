import SwiftUI

struct ScreenshotEditorView: View {
    @StateObject private var viewModel: ScreenshotEditorViewModel
    let onCopy: (NSImage) -> Void
    let onClose: () -> Void
    
    init(originalImage: NSImage, onCopy: @escaping (NSImage) -> Void, onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ScreenshotEditorViewModel(image: originalImage))
        self.onCopy = onCopy
        self.onClose = onClose
    }
    
    var body: some View {
        Text("Editor - À compléter")
    }
}