import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - ScreenshotRenderer

/// Optimized renderer for exporting screenshots with noise via CIKernel.
final class ScreenshotRenderer {
    let image: NSImage
    let config: ScreenshotStyleConfig
    
    // Core Image context (reused for performance)
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // CIColorKernel for noise (CISL code - identical to Metal shader)
    private static let noiseKernel: CIColorKernel? = {
        // CISL kernel that matches the SwiftUI Metal shader exactly
        // destCoord() returns the current pixel coordinates
        let kernelCode = """
        kernel vec4 noiseKernel(__sample pixel, float intensity) {
            vec2 coord = destCoord();
            
            // Generate fine grain noise (0 to 1) - IDENTICAL to Metal shader
            float value = fract(sin(dot(coord, vec2(12.9898, 78.233))) * 43758.5453);
            
            // Center at 0.5 and scale by intensity - IDENTICAL to Metal shader
            float grain = 0.5 + (value - 0.5) * intensity * 0.7;
            
            // Apply soft light blend
            vec3 base = pixel.rgb;
            vec3 result;
            
            // Soft light formula for each channel
            float b0 = base.r;
            float b1 = base.g;
            float b2 = base.b;
            
            if (grain <= 0.5) {
                result.r = b0 - (1.0 - 2.0 * grain) * b0 * (1.0 - b0);
                result.g = b1 - (1.0 - 2.0 * grain) * b1 * (1.0 - b1);
                result.b = b2 - (1.0 - 2.0 * grain) * b2 * (1.0 - b2);
            } else {
                float d0 = (b0 <= 0.25) ? ((16.0 * b0 - 12.0) * b0 + 4.0) * b0 : sqrt(b0);
                float d1 = (b1 <= 0.25) ? ((16.0 * b1 - 12.0) * b1 + 4.0) * b1 : sqrt(b1);
                float d2 = (b2 <= 0.25) ? ((16.0 * b2 - 12.0) * b2 + 4.0) * b2 : sqrt(b2);
                result.r = b0 + (2.0 * grain - 1.0) * (d0 - b0);
                result.g = b1 + (2.0 * grain - 1.0) * (d1 - b1);
                result.b = b2 + (2.0 * grain - 1.0) * (d2 - b2);
            }
            
            return vec4(result, pixel.a);
        }
        """
        
        return CIColorKernel(source: kernelCode)
    }()
    
    // MARK: - Dynamic Scale Based on Output Size
    
    private var optimalScale: CGFloat {
        let outputWidth = calculateOutputSize().width
        
        if outputWidth > 3000 {
            return 1.0
        } else if outputWidth > 2000 {
            return 1.5
        } else {
            return 2.0
        }
    }
    
    init(image: NSImage, config: ScreenshotStyleConfig) {
        self.image = image
        self.config = config
    }
    
    // MARK: - Render (sync)
    func render() -> NSImage? {
        var preloadedBackgroundImage: NSImage? = nil
        if config.backgroundType == .image, let url = config.backgroundImageURL {
            preloadedBackgroundImage = ImageLoadingService.shared.loadImageSync(from: url, maxDimension: 8192)
        }
        return performRender(preloadedBackgroundImage: preloadedBackgroundImage)
    }
    
    // MARK: - Render (async)
    func renderAsync() async -> NSImage? {
        var preloadedBackgroundImage: NSImage? = nil
        if config.backgroundType == .image, let url = config.backgroundImageURL {
            preloadedBackgroundImage = await ImageLoadingService.shared.loadImage(from: url, maxDimension: 8192)
        }
        return await MainActor.run {
            performRender(preloadedBackgroundImage: preloadedBackgroundImage)
        }
    }
    
    // MARK: - Core Render Logic (shared)
    private func performRender(preloadedBackgroundImage: NSImage?) -> NSImage? {
        var exportConfig = config
        exportConfig.zoom = 100
        
        let outputSize = calculateOutputSize()
        
        // Render main canvas
        guard let baseImage = renderCanvas(config: exportConfig, size: outputSize, preloadedBackground: preloadedBackgroundImage) else {
            return nil
        }
        
        // Apply noise if needed (noise goes UNDER screenshot)
        guard config.gradientConfig.noiseAmount > 0 else {
            return baseImage
        }
        
        guard let noisyImage = applyNoise(to: baseImage, intensity: config.gradientConfig.noiseAmount / 100) else {
            return baseImage
        }
        
        // Render screenshot only (transparent background) to composite on top
        var transparentConfig = exportConfig
        transparentConfig.backgroundType = .transparent
        
        guard let screenshotLayer = renderCanvas(config: transparentConfig, size: outputSize, preloadedBackground: nil) else {
            return noisyImage
        }
        
        return compositeImages(background: noisyImage, foreground: screenshotLayer, size: outputSize)
    }
    
    // MARK: - Render Canvas Helper
    private func renderCanvas(config: ScreenshotStyleConfig, size: CGSize, preloadedBackground: NSImage?) -> NSImage? {
        let view = ScreenshotPreviewCanvas(
            image: image,
            config: config,
            isDragging: .constant(false),
            isRendering: true,
            preloadedBackgroundImage: preloadedBackground
        )
        
        let sizedView = view.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: sizedView)
        renderer.scale = optimalScale
        
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }
    
    // MARK: - Composite Images
    private func compositeImages(background: NSImage, foreground: NSImage, size: CGSize) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        background.draw(in: NSRect(origin: .zero, size: size))
        foreground.draw(in: NSRect(origin: .zero, size: size))
        result.unlockFocus()
        return result
    }
    
    // MARK: - Noise Application (uses CIColorKernel - identical to SwiftUI shader)
    private func applyNoise(to nsImage: NSImage, intensity: Double) -> NSImage? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let inputImage = CIImage(cgImage: cgImage)
        let extent = inputImage.extent
        
        // Use CIColorKernel (exact same algorithm as SwiftUI Metal shader)
        if let kernel = Self.noiseKernel {
            // Arguments: sampler (pixel), intensity
            // destCoord() is called inside the kernel to get coordinates
            let arguments: [Any] = [
                CISampler(image: inputImage),
                Float(intensity)
            ]
            
            guard let outputImage = kernel.apply(extent: extent, arguments: arguments) else {
                print("CIColorKernel apply failed, using fallback")
                return applyNoiseFallback(to: nsImage, inputImage: inputImage, intensity: intensity)
            }
            
            guard let finalCGImage = Self.ciContext.createCGImage(outputImage, from: extent) else { return nil }
            return NSImage(cgImage: finalCGImage, size: nsImage.size)
        }
        
        // Fallback: Core Image filters (if kernel fails to load)
        print("CIColorKernel not available, using fallback")
        return applyNoiseFallback(to: nsImage, inputImage: inputImage, intensity: intensity)
    }
    
    // MARK: - Fallback Noise (Core Image filters)
    private func applyNoiseFallback(to nsImage: NSImage, inputImage: CIImage, intensity: Double) -> NSImage? {
        let extent = inputImage.extent
        
        // Generate noise with CIRandomGenerator
        guard let noiseGenerator = CIFilter(name: "CIRandomGenerator"),
              let noiseOutput = noiseGenerator.outputImage else { return nil }
        
        let croppedNoise = noiseOutput.cropped(to: extent)
        
        // Convert to grayscale
        let grayNoise = croppedNoise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputGVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputBVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        
        // Soft light blend
        guard let blendFilter = CIFilter(name: "CISoftLightBlendMode") else { return nil }
        blendFilter.setValue(grayNoise, forKey: kCIInputImageKey)
        blendFilter.setValue(inputImage, forKey: kCIInputBackgroundImageKey)
        
        guard let blendedOutput = blendFilter.outputImage else { return nil }
        
        // Mix based on intensity
        let effectiveIntensity = intensity * 0.7
        
        guard let mixFilter = CIFilter(name: "CIDissolveTransition") else { return nil }
        mixFilter.setValue(inputImage, forKey: kCIInputImageKey)
        mixFilter.setValue(blendedOutput, forKey: kCIInputTargetImageKey)
        mixFilter.setValue(effectiveIntensity, forKey: kCIInputTimeKey)
        
        guard let finalOutput = mixFilter.outputImage,
              let finalCGImage = Self.ciContext.createCGImage(finalOutput, from: extent) else { return nil }
        
        return NSImage(cgImage: finalCGImage, size: nsImage.size)
    }
    
    // MARK: - Size Calculations
    
    private func calculateOutputSize() -> CGSize {
        let mockupPadding = mockupExtraPadding()
        let baseWidth = image.size.width + config.padding * 2 + mockupPadding.width
        let baseHeight = image.size.height + config.padding * 2 + mockupPadding.height
        
        // If a social preset is selected, use its dimensions
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
