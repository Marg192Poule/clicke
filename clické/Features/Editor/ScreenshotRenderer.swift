import SwiftUI
import AppKit
import AVFoundation

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
        
        // Preload background image synchronously if needed
        var preloadedBackgroundImage: NSImage? = nil
        if config.backgroundType == .image, let url = config.backgroundImageURL {
            preloadedBackgroundImage = loadBackgroundImage(from: url)
        }
        
        // Create the preview canvas view with isRendering=true for transparent background
        let view = ScreenshotPreviewCanvas(
            image: image,
            config: exportConfig,
            isDragging: .init(get: { false }, set: { _ in }),
            isRendering: true,
            preloadedBackgroundImage: preloadedBackgroundImage
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
    
    // MARK: - Background Image Loading
    private func loadBackgroundImage(from url: URL) -> NSImage? {
        let videoExtensions = ["mov", "mp4"]
        let isVideo = videoExtensions.contains(url.pathExtension.lowercased())
        
        if isVideo {
            return extractFrameFromVideo(url: url)
        } else {
            return loadImageFromFile(url: url)
        }
    }
    
    private func loadImageFromFile(url: URL) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        
        // For HEIC files, use CIImage for better compatibility
        if ext == "heic" || ext == "heif" {
            guard let ciImage = CIImage(contentsOf: url) else { return nil }
            let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        
        // Standard image loading
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    private func extractFrameFromVideo(url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = CMTime.zero
        generator.requestedTimeToleranceBefore = CMTime.zero
        generator.maximumSize = CGSize(width: 3840, height: 2160)
        
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultImage: NSImage? = nil
        
        generator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
            if let cgImage = cgImage {
                resultImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let image = resultImage {
            return image
        }
        
        // Try at 0 seconds if first attempt failed
        let semaphore2 = DispatchSemaphore(value: 0)
        resultImage = nil
        
        generator.generateCGImageAsynchronously(for: .zero) { cgImage, actualTime, error in
            if let cgImage = cgImage {
                resultImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            semaphore2.signal()
        }
        
        semaphore2.wait()
        return resultImage
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
        case .defaultStyle:
            return .zero
        case .glassEffect, .border:
            let size = config.mockupBorderSize * 3 * 2
            return CGSize(width: size, height: size)
        }
    }
}
