import SwiftUI
import AppKit
internal import Combine

class ScreenshotEditorViewModel: ObservableObject {
    @Published var config = ScreenshotStyleConfig.default
    let originalImage: NSImage
    
    init(image: NSImage) {
        self.originalImage = image
    }
}
