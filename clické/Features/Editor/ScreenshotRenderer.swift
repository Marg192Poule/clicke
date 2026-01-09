import SwiftUI
import AppKit

// MARK: - ScreenshotRenderer
/// Renderer optimisé pour l'export de screenshots
final class ScreenshotRenderer {
    let image: NSImage
    let config: ScreenshotStyleConfig
    
    // MARK: - Scale dynamique basé sur la taille de sortie
    private var optimalScale: CGFloat {
        let outputWidth = calculateOutputSize().width
        
        // Ajuster le scale en fonction de la taille de sortie
        // Plus l'image est grande, moins on a besoin de scale élevé
        if outputWidth > 3000 {
            return 1.0  // 4K+ : pas besoin de upscale
        } else if outputWidth > 2000 {
            return 1.5  // 2K-4K : léger upscale
        } else {
            return 2.0  // Standard : upscale x2 pour la qualité
        }
    }
    
    init(image: NSImage, config: ScreenshotStyleConfig) {
        self.image = image
        self.config = config
    }
    
    // MARK: - Render
    func render() -> NSImage? {
        var exportConfig = config
        exportConfig.zoom = 100
        
        // Précharger l'image de fond via le service centralisé
        var preloadedBackgroundImage: NSImage? = nil
        if config.backgroundType == .image, let url = config.backgroundImageURL {
            preloadedBackgroundImage = ImageLoadingService.shared.loadImageSync(from: url)
        }
        
        let view = ScreenshotPreviewCanvas(
            image: image,
            config: exportConfig,
            isDragging: .constant(false),
            isRendering: true,
            preloadedBackgroundImage: preloadedBackgroundImage
        )
        
        let outputSize = calculateOutputSize()
        let sizedView = view.frame(width: outputSize.width, height: outputSize.height)
        
        let renderer = ImageRenderer(content: sizedView)
        renderer.scale = optimalScale
        
        guard let cgImage = renderer.cgImage else { return nil }
        
        return NSImage(cgImage: cgImage, size: outputSize)
    }
    
    // MARK: - Async Render (préféré pour les grandes images)
    func renderAsync() async -> NSImage? {
        var exportConfig = config
        exportConfig.zoom = 100
        
        // Précharger l'image de fond de manière asynchrone
        var preloadedBackgroundImage: NSImage? = nil
        if config.backgroundType == .image, let url = config.backgroundImageURL {
            preloadedBackgroundImage = await ImageLoadingService.shared.loadImage(from: url)
        }
        
        return await MainActor.run {
            let view = ScreenshotPreviewCanvas(
                image: image,
                config: exportConfig,
                isDragging: .constant(false),
                isRendering: true,
                preloadedBackgroundImage: preloadedBackgroundImage
            )
            
            let outputSize = calculateOutputSize()
            let sizedView = view.frame(width: outputSize.width, height: outputSize.height)
            
            let renderer = ImageRenderer(content: sizedView)
            renderer.scale = optimalScale
            
            guard let cgImage = renderer.cgImage else { return nil }
            
            return NSImage(cgImage: cgImage, size: outputSize)
        }
    }
    
    // MARK: - Size Calculations
    
    private func calculateOutputSize() -> CGSize {
        let mockupPadding = mockupExtraPadding()
        let baseWidth = image.size.width + config.padding * 2 + mockupPadding.width
        let baseHeight = image.size.height + config.padding * 2 + mockupPadding.height
        
        // Si un preset social est sélectionné, utiliser ses dimensions
        if let preset = config.selectedSocialPreset {
            return CGSize(width: CGFloat(preset.width), height: CGFloat(preset.height))
        }
        
        // Tenir compte de la rotation
        let rotatedSize = calculateRotatedSize(width: baseWidth, height: baseHeight, rotation: config.rotation)
        
        return CGSize(
            width: rotatedSize.width * config.scale,
            height: rotatedSize.height * config.scale
        )
    }
    
    private func calculateRotatedSize(width: CGFloat, height: CGFloat, rotation: Double) -> CGSize {
        let radians = rotation * .pi / 180
        let cos = abs(Darwin.cos(radians))
        let sin = abs(Darwin.sin(radians))
        
        return CGSize(
            width: width * cos + height * sin,
            height: width * sin + height * cos
        )
    }
    
    private func mockupExtraPadding() -> CGSize {
        guard config.showMockup else { return .zero }
        
        switch config.mockupStyle {
        case .defaultStyle:
            return .zero
        case .glassEffect, .border:
            let size = config.mockupBorderSize * 3 * 2
            return CGSize(width: size, height: size)
        }
    }
}
