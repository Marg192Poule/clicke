import SwiftUI
import AppKit
import AVFoundation

struct ScreenshotPreviewCanvas: View {
    let image: NSImage
    let config: ScreenshotStyleConfig
    @Binding var isDragging: Bool
    var onScreenshotOffsetChanged: ((CGSize) -> Void)? = nil
    var isRendering: Bool = false // True when rendering for export, false for preview
    var preloadedBackgroundImage: NSImage? = nil // Preloaded image for export rendering
    
    private let canvasCornerRadius: CGFloat = 24
    @State private var dragOffset: CGSize = .zero
    @State private var loadedBackgroundImage: NSImage? = nil
    
    var body: some View {
        ZStack {
            // Background with unified blur (except transparent)
            // Use drawingGroup to rasterize to GPU texture - prevents re-rendering during 3D rotations
            if config.backgroundType == .transparent {
                backgroundView
            } else {
                backgroundView
                    .blur(radius: config.gradientConfig.blurAmount)
                    .drawingGroup(opaque: true, colorMode: .linear) // Rasterize to GPU texture for smooth 3D rotations
                
                // Noise overlay as separate layer (not affected by blur)
                // Skip noise texture during export rendering (Metal shaders don't work with ImageRenderer)
                if config.gradientConfig.noiseAmount > 0 && !isRendering {
                    NoiseTextureView(intensity: config.gradientConfig.noiseAmount / 100)
                }
            }
            
            // Shadow scene underlay
            if config.shadowSceneMode == .underlay && config.selectedShadowScene != nil {
                shadowSceneOverlay
                    .opacity(config.shadowSceneOpacity / 100)
            }
            
            // Screenshot with transforms applied
            Group {
                if config.selectedSocialPreset != nil {
                    // Quand un preset social est sélectionné, adapter l'échelle
                    screenshotContent
                        .scaleEffect(socialPresetImageScale)
                } else {
                    screenshotContent
                        .scaleEffect(config.imageScale / 100)
                }
            }
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
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: config.rotation)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: config.rotationX)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: config.rotationY)
            .animation(.easeOut(duration: 0.2), value: config.scale)
            .animation(.easeOut(duration: 0.15), value: config.imageScale)
            .animation(.easeOut(duration: 0.2), value: config.borderRadius)
            .offset(CGSize(width: config.screenshotOffset.width + dragOffset.width, height: config.screenshotOffset.height + dragOffset.height))
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let newOffset = CGSize(
                            width: config.screenshotOffset.width + value.translation.width,
                            height: config.screenshotOffset.height + value.translation.height
                        )
                        onScreenshotOffsetChanged?(newOffset)
                        dragOffset = .zero
                        isDragging = false
                    }
            )
            
            // Shadow scene overlay
            if config.shadowSceneMode == .overlay && config.selectedShadowScene != nil {
                shadowSceneOverlay
                    .opacity(config.shadowSceneOpacity / 100)
                    .blendMode(.overlay)
            }
            
            // Text overlays
            ForEach(config.textOverlays) { overlay in
                textOverlayView(overlay)
            }
            
            // Note: Redact regions are rendered in ScreenshotEditorView overlay
            // to maintain correct screen-space coordinates during editing
        }
        .frame(width: totalWidth, height: totalHeight)
        .clipShape(RoundedRectangle(cornerRadius: canvasCornerRadius))
    }
    
    // MARK: - Text Overlay View
    @ViewBuilder
    private func textOverlayView(_ overlay: TextOverlay) -> some View {
        Text(overlay.text)
            .font(.system(size: overlay.fontSize, weight: overlay.fontWeight))
            .foregroundColor(overlay.color)
            .opacity(overlay.opacity)
            .blur(radius: overlay.isBlurred ? 8 : 0)
            .rotationEffect(.degrees(overlay.rotation))
            .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)
    }
    
    // MARK: - Redact Region View
    @ViewBuilder
    private func redactRegionView(_ region: RedactRegion) -> some View {
        Group {
            switch region.style {
            case .blur:
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: 10)
            case .pixelate:
                PixelateView()
            case .blackBar:
                Rectangle()
                    .fill(Color.black)
            }
        }
        .frame(width: region.rect.width, height: region.rect.height)
        .position(x: region.rect.midX, y: region.rect.midY)
    }
    
    // Shadow scene decorative overlay
    @ViewBuilder
    private var shadowSceneOverlay: some View {
        if let scene = config.selectedShadowScene {
            LinearGradient(
                colors: scene.colors.map { $0.opacity(0.3) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .mask {
                // Create shadow pattern
                Canvas { context, size in
                    // Draw diagonal shadow lines
                    for i in stride(from: -size.height, to: size.width + size.height, by: 40) {
                        var path = Path()
                        path.move(to: CGPoint(x: i, y: 0))
                        path.addLine(to: CGPoint(x: i + size.height, y: size.height))
                        context.stroke(path, with: .color(.white), lineWidth: 20)
                    }
                }
            }
        }
    }
    
    // MARK: - Dimensions
    private var totalWidth: CGFloat {
        // Si un preset social est sélectionné, utiliser ses dimensions
        if let preset = config.selectedSocialPreset {
            return CGFloat(preset.width)
        }
        return image.size.width + config.padding * 2 + extraPadding.width
    }
    
    private var totalHeight: CGFloat {
        // Si un preset social est sélectionné, utiliser ses dimensions
        if let preset = config.selectedSocialPreset {
            return CGFloat(preset.height)
        }
        return image.size.height + config.padding * 2 + extraPadding.height
    }
    
    // Calculer l'échelle pour adapter l'image au format social
    private var socialPresetImageScale: CGFloat {
        guard let preset = config.selectedSocialPreset else { return 1.0 }
        
        let presetWidth = CGFloat(preset.width)
        let presetHeight = CGFloat(preset.height)
        let imageWidth = image.size.width + config.padding * 2
        let imageHeight = image.size.height + config.padding * 2
        
        // Adapter l'image avec une marge
        let availableWidth = presetWidth - 40 // 20px de marge de chaque côté
        let availableHeight = presetHeight - 40
        
        let scaleX = availableWidth / imageWidth
        let scaleY = availableHeight / imageHeight
        
        return min(scaleX, scaleY, 1.0) * (config.imageScale / 100)
    }
    
    private var extraPadding: CGSize {
        // Mockup styles
        guard config.showMockup else { return .zero }
        
        switch config.mockupStyle {
        case .defaultStyle:
            return .zero
        case .glassEffect, .border:
            let size = config.mockupBorderSize * 3 * 2 // padding * 2 pour width et height
            return CGSize(width: size, height: size)
        }
    }
    
    // MARK: - Screenshot Content
    @ViewBuilder
    private var screenshotContent: some View {
        contentView
    }
    
    @ViewBuilder
    private var contentView: some View {
        if config.showMockup {
            // Mockup style mode
            styledScreenshot
        } else {
            // Plain screenshot
            Image(nsImage: image)
                .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
        }
    }
    
    // MARK: - Background
    @ViewBuilder
    private var backgroundView: some View {
        Group {
            switch config.backgroundType {
            case .transparent:
                if isRendering {
                    // Use transparent background when rendering for export
                    Color.clear
                } else {
                    // Use checkerboard for preview
                    CheckerboardView()
                }
                
            case .color:
                colorBackground
                
            case .image:
                imageBackground
                
            case .gradient:
                gradientBackground
            }
        }
    }
    
    @ViewBuilder
    private var gradientBackground: some View {
        config.gradientConfig.gradientView(size: CGSize(width: totalWidth, height: totalHeight), isRendering: isRendering)
    }
    
    @ViewBuilder
    private var colorBackground: some View {
        Group {
            if let magic = config.selectedMagicPreset {
                magicGradient(magic)
            } else if let scene = config.selectedShadowScene {
                sceneBackground(scene)
            } else if let solid = config.selectedSolidColor {
                solid.color
            } else if let gradient = config.selectedGradient {
                LinearGradient(colors: gradient.colors, startPoint: .leading, endPoint: .trailing)
            } else {
                config.customColor
            }
        }
        // Color adjustments: Use SwiftUI native modifiers during export (Metal shaders don't work with ImageRenderer)
        .saturation(isRendering ? config.gradientConfig.saturation / 100 : 1.0)
        .brightness(isRendering ? (config.gradientConfig.brightness - 100) / 100 : 0.0)
        .colorAdjustments(
            saturation: isRendering ? 1.0 : config.gradientConfig.saturation / 100,
            brightness: isRendering ? 0.0 : (config.gradientConfig.brightness - 100) / 100
        )
    }
    
    @ViewBuilder
    private var imageBackground: some View {
        Group {
            if config.backgroundImageURL != nil {
                // Use preloaded image for export, or cached image for preview
                if let preloaded = preloadedBackgroundImage {
                    Image(nsImage: preloaded)
                        .resizable()
                        .scaledToFill()
                } else if let cachedImage = loadedBackgroundImage {
                    Image(nsImage: cachedImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Show color background immediately while loading
                    colorBackground
                }
            } else if let scene = config.selectedShadowScene {
                sceneBackground(scene)
            } else {
                colorBackground
            }
        }
        // Color adjustments: Use SwiftUI native modifiers for images (faster than Metal shaders for large images)
        // Native modifiers are GPU-optimized and cached by SwiftUI
        .saturation(config.gradientConfig.saturation / 100)
        .brightness((config.gradientConfig.brightness - 100) / 100)
        .onChange(of: config.backgroundImageURL?.absoluteString) { _, newValue in
            // Reset and load new image asynchronously
            loadedBackgroundImage = nil
            if let urlString = newValue, let newURL = URL(string: urlString) {
                loadBackgroundImageAsync(from: newURL)
            }
        }
        .onAppear {
            // Load on appear if URL exists and image not loaded
            if let url = config.backgroundImageURL, loadedBackgroundImage == nil {
                loadBackgroundImageAsync(from: url)
            }
        }
    }
    
    /// Load and optimize background image asynchronously
    private func loadBackgroundImageAsync(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let videoExtensions = ["mov", "mp4"]
            let isVideo = videoExtensions.contains(url.pathExtension.lowercased())
            let loadedImage: NSImage?
            if isVideo {
                loadedImage = extractFrameFromVideo(url: url)
            } else {
                loadedImage = loadImageFromFile(url: url)
            }
            // Downscale for preview performance (max 2K resolution)
            let optimizedImage = loadedImage?.resizedForPreview(maxDimension: 2048)
            DispatchQueue.main.async {
                loadedBackgroundImage = optimizedImage ?? loadedImage
            }
        }
    }
    
    // Load image from file, handling HEIC conversion (optimized)
    private func loadImageFromFile(url: URL) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        
        // For HEIC files, use CIImage for better compatibility
        if ext == "heic" || ext == "heif" {
            guard let ciImage = CIImage(contentsOf: url) else { return nil }
            let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        
        // Standard image loading for other formats - use image source for better performance
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
        generator.maximumSize = CGSize(width: 3840, height: 2160) // 4K max for quality
        
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        
        // Use the new async API with semaphore to maintain synchronous behavior
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
    
    @ViewBuilder
    private func magicGradient(_ magic: MagicPreset) -> some View {
        if magic.colors.count == 1 {
            magic.colors[0]
        } else {
            LinearGradient(colors: magic.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    @ViewBuilder
    private func sceneBackground(_ scene: ShadowScene) -> some View {
        // Use Metal shader for noise instead of CPU-intensive Canvas
        // Skip noise during export rendering (Metal shaders don't work with ImageRenderer)
        if isRendering {
            LinearGradient(colors: scene.colors, startPoint: .top, endPoint: .bottom)
        } else {
            LinearGradient(colors: scene.colors, startPoint: .top, endPoint: .bottom)
                .noiseOverlay(intensity: 0.15) // Subtle noise via GPU shader
        }
    }
    
    // MARK: - Styled Screenshot
    @ViewBuilder
    private var styledScreenshot: some View {
        switch config.mockupStyle {
        case .defaultStyle:
            Image(nsImage: image)
                .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
        case .glassEffect:
            glassEffectMockup
        case .border:
            borderMockup
        }
    }
    
    // MARK: - Mockup Styles
    
    private var glassEffectMockup: some View {
        let borderWidth = config.mockupBorderSize * 3 // Épaisseur du contour glass
        let cornerRadius = config.borderRadius + borderWidth * 0.5
        
        return Image(nsImage: image)
            .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
            .padding(borderWidth)
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    private var borderMockup: some View {
        let borderWidth = config.mockupBorderSize * 3 // Épaisseur du contour
        
        return Image(nsImage: image)
            .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
            .padding(borderWidth)
            .background {
                RoundedRectangle(cornerRadius: config.borderRadius + borderWidth * 0.5)
                    .fill(config.borderColor)
            }
    }
}

// MARK: - Checkerboard View (GPU-accelerated)
struct CheckerboardView: View {
    let squareSize: CGFloat = 12
    
    var body: some View {
        // Use Metal shader for GPU-accelerated checkerboard
        CheckerboardShaderView(squareSize: squareSize)
    }
}

// MARK: - Noise View (GPU-accelerated - uses Metal shader)
struct NoiseView: View {
    let intensity: Double // 0 to 1
    
    var body: some View {
        // Use Metal shader instead of Canvas for GPU acceleration
        Rectangle()
            .fill(Color.clear)
            .noiseOverlay(intensity: intensity)
            .allowsHitTesting(false)
    }
}

// MARK: - Pixelate View (GPU-accelerated)
struct PixelateView: View {
    var body: some View {
        // Use Metal shader for GPU-accelerated pixelation (no flickering)
        PixelateShaderView(pixelSize: 8)
    }
}