import SwiftUI
import AppKit

class ScreenshotRenderer {
    let image: NSImage
    let config: ScreenshotStyleConfig

    init(image: NSImage, config: ScreenshotStyleConfig) {
        self.image = image
        self.config = config
    }
    
    func render() -> NSImage? {
        // Create config for clean export (zoom at 100%, no offset)
        var exportConfig = config
        exportConfig.zoom = 100
        
        // Create the preview canvas view with isRendering=true for transparent background
        let view = ScreenshotPreviewCanvas(image: image, config: exportConfig, isDragging: .init(get: { false }, set: { _ in }), isRendering: true)
            .scaleEffect(config.scale)
            .rotationEffect(.degrees(config.rotation))
            .rotation3DEffect(
                .degrees(config.rotationX),
                axis: (x: 1, y: 0, z: 0),
                perspective: (config.rotationX != 0 || config.rotationY != 0) ? 1.0 : 0
            )
            .rotation3DEffect(
                .degrees(config.rotationY),
                axis: (x: 0, y: 1, z: 0),
                perspective: (config.rotationX != 0 || config.rotationY != 0) ? 1.0 : 0
            )
        
        // Calculate size
        let mockupPadding = mockupExtraPadding()
        let baseWidth = image.size.width + config.padding * 2 + mockupPadding.width
        let baseHeight = image.size.height + config.padding * 2 + mockupPadding.height
        
        // Account for rotation
        let rotatedSize = calculateRotatedSize(width: baseWidth, height: baseHeight, rotation: config.rotation)
        
        let width = rotatedSize.width * config.scale
        let height = rotatedSize.height * config.scale
        
        let sizedView = view.frame(width: width, height: height)
        
        let renderer = ImageRenderer(content: sizedView)
        renderer.scale = 2.0
        
        guard let cgImage = renderer.cgImage else { return nil }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
    
    private func calculateRotatedSize(width: CGFloat, height: CGFloat, rotation: Double) -> CGSize {
        let radians = rotation * .pi / 180
        let cos = abs(Darwin.cos(radians))
        let sin = abs(Darwin.sin(radians))
        
        let newWidth = width * cos + height * sin
        let newHeight = width * sin + height * cos
        
        return CGSize(width: newWidth, height: newHeight)
    }
    
    private func mockupExtraPadding() -> CGSize {
        guard config.showMockup else { return .zero }
        
        switch config.mockupStyle {
        case .defaultStyle, .outline:
            return .zero
        case .glassLight, .glassDark:
            return CGSize(width: 12, height: 12)
        case .liquidGlass:
            return CGSize(width: 20, height: 20)
        case .insetLight, .insetDark:
            return CGSize(width: 28, height: 28)
        case .border:
            return CGSize(width: 6, height: 6)
        }
    }
}
