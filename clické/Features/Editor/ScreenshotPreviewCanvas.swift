import SwiftUI
import AppKit
import AVFoundation

struct ScreenshotPreviewCanvas: View {
    let image: NSImage
    let config: ScreenshotStyleConfig
    @Binding var isDragging: Bool
    var onScreenshotOffsetChanged: ((CGSize) -> Void)? = nil
    var isRendering: Bool = false // True when rendering for export, false for preview
    
    private let canvasCornerRadius: CGFloat = 24
    @State private var dragOffset: CGSize = .zero
    @State private var loadedBackgroundImage: NSImage? = nil
    
    var body: some View {
        ZStack {
            // Background with effects
            backgroundView
                .overlay {
                    // Noise overlay (applied first)
                    if config.backgroundNoise > 0 {
                        NoiseView(intensity: config.backgroundNoise / 100)
                    }
                }
                .blur(radius: config.backgroundBlur / 5) // Blur applied on top of noise
            
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
        case .defaultStyle, .outline:
            return .zero
        case .glassLight, .glassDark:
            return CGSize(width: config.mockupBorderSize, height: config.mockupBorderSize)
        case .liquidGlass:
            let borderSize = config.mockupBorderSize * 1.67
            return CGSize(width: borderSize, height: borderSize)
        case .insetLight, .insetDark:
            let outerSize = config.mockupBorderSize * 2.33
            return CGSize(width: outerSize, height: outerSize)
        case .border:
            let borderSize = config.mockupBorderSize * 0.5
            return CGSize(width: borderSize, height: borderSize)
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
        config.meshGradientConfig.gradientView(size: CGSize(width: totalWidth, height: totalHeight))
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
        .saturation(config.meshGradientConfig.saturation / 100)
        .brightness((config.meshGradientConfig.brightness - 100) / 100)
    }
    
    @ViewBuilder
    private var imageBackground: some View {
        Group {
            if config.backgroundImageURL != nil {
                // Show immediately with cached image or fallback, load async
                if let cachedImage = loadedBackgroundImage {
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
        .saturation(config.meshGradientConfig.saturation / 100)
        .brightness((config.meshGradientConfig.brightness - 100) / 100)
        .onChange(of: config.backgroundImageURL) { _, newURL in
            // Reset and load new image asynchronously
            loadedBackgroundImage = nil
            if let newURL = newURL {
                DispatchQueue.global(qos: .userInitiated).async {
                    let videoExtensions = ["mov", "mp4"]
                    let isVideo = videoExtensions.contains(newURL.pathExtension.lowercased())
                    let loadedImage: NSImage?
                    if isVideo {
                        loadedImage = extractFrameFromVideo(url: newURL)
                    } else {
                        loadedImage = loadImageFromFile(url: newURL)
                    }
                    DispatchQueue.main.async {
                        loadedBackgroundImage = loadedImage
                    }
                }
            }
        }
        .onAppear {
            // Load on appear if URL exists and image not loaded
            if let url = config.backgroundImageURL, loadedBackgroundImage == nil {
                DispatchQueue.global(qos: .userInitiated).async {
                    let videoExtensions = ["mov", "mp4"]
                    let isVideo = videoExtensions.contains(url.pathExtension.lowercased())
                    let loadedImage: NSImage?
                    if isVideo {
                        loadedImage = extractFrameFromVideo(url: url)
                    } else {
                        loadedImage = loadImageFromFile(url: url)
                    }
                    DispatchQueue.main.async {
                        loadedBackgroundImage = loadedImage
                    }
                }
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
        ZStack {
            LinearGradient(colors: scene.colors, startPoint: .top, endPoint: .bottom)
            noiseTexture
        }
    }
    
    private var noiseTexture: some View {
        Canvas { context, size in
            for _ in 0..<Int(size.width * size.height / 500) {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                let opacity = Double.random(in: 0.01...0.05)
                context.fill(
                    Circle().path(in: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
    }
    
    // MARK: - Styled Screenshot
    @ViewBuilder
    private var styledScreenshot: some View {
        switch config.mockupStyle {
        case .defaultStyle:
            Image(nsImage: image)
                .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
        case .glassLight:
            glassMockup(isDark: false)
        case .glassDark:
            glassMockup(isDark: true)
        case .liquidGlass:
            liquidGlassMockup
        case .insetLight:
            insetMockup(isDark: false)
        case .insetDark:
            insetMockup(isDark: true)
        case .outline:
            outlineMockup
        case .border:
            borderMockup
        }
    }
    
    // MARK: - Mockup Styles
    
    private func glassMockup(isDark: Bool) -> some View {
        let frameColor = isDark ? Color(hex: "1c1c1e") : Color(hex: "f5f5f7")
        let borderColor = isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
        let borderSize = config.mockupBorderSize
        
        return ZStack {
            if borderSize > 0 {
                RoundedRectangle(cornerRadius: config.borderRadius + borderSize * 0.5)
                    .fill(frameColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: config.borderRadius + borderSize * 0.5)
                            .stroke(borderColor, lineWidth: 0.5)
                    )
                    .frame(width: image.size.width + borderSize, height: image.size.height + borderSize)
            }
            
            Image(nsImage: image)
                .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
        }
    }
    
    private var liquidGlassMockup: some View {
        let borderSize = config.mockupBorderSize * 1.67 // Proportion par rapport à glass
        
        return ZStack {
            if borderSize > 0 {
                RoundedRectangle(cornerRadius: config.borderRadius + borderSize * 0.5)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: config.borderRadius + borderSize * 0.5)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .frame(width: image.size.width + borderSize, height: image.size.height + borderSize)
            }
            
            Image(nsImage: image)
                .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
        }
    }
    
    private func insetMockup(isDark: Bool) -> some View {
        let outerColor = isDark ? Color(hex: "1a1a1a") : Color(hex: "f0f0f0")
        let innerColor = isDark ? Color(hex: "0d0d0d") : Color(hex: "e0e0e0")
        let outerSize = config.mockupBorderSize * 2.33 // Proportion pour le contour extérieur
        let innerSize = config.mockupBorderSize * 0.67 // Proportion pour le contour intérieur
        
        return ZStack {
            if outerSize > 0 {
                RoundedRectangle(cornerRadius: config.borderRadius + outerSize * 0.5)
                    .fill(outerColor)
                    .frame(width: image.size.width + outerSize, height: image.size.height + outerSize)
            }
            
            if innerSize > 0 {
                RoundedRectangle(cornerRadius: config.borderRadius + innerSize * 0.5)
                    .fill(innerColor)
                    .frame(width: image.size.width + innerSize, height: image.size.height + innerSize)
            }
            
            Image(nsImage: image)
                .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
        }
    }
    
    private var outlineMockup: some View {
        Image(nsImage: image)
            .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
            .overlay(
                RoundedRectangle(cornerRadius: config.borderRadius)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
            )
    }
    
    private var borderMockup: some View {
        let borderSize = config.mockupBorderSize * 0.5 // Plus fin que glass
        
        return ZStack {
            if borderSize > 0 {
                RoundedRectangle(cornerRadius: config.borderRadius + borderSize * 0.5)
                    .fill(Color(hex: "2d2d2d"))
                    .frame(width: image.size.width + borderSize, height: image.size.height + borderSize)
            }
            
            Image(nsImage: image)
                .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
        }
    }
}

// MARK: - Checkerboard View
struct CheckerboardView: View {
    let squareSize: CGFloat = 12
    
    var body: some View {
        Canvas { context, size in
            let rows = Int(size.height / squareSize) + 1
            let cols = Int(size.width / squareSize) + 1
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(
                        Rectangle().path(in: rect),
                        with: .color(isLight ? Color(hex: "3a3a3a") : Color(hex: "2a2a2a"))
                    )
                }
            }
        }
    }
}

// MARK: - Noise View (Optimized with static pattern)
struct NoiseView: View {
    let intensity: Double // 0 to 1
    
    // Use a static seed for consistent noise pattern
    private static let noisePattern: [[Double]] = {
        var pattern: [[Double]] = []
        let rows = 150 // Fixed pattern size
        let cols = 200
        for _ in 0..<rows {
            var row: [Double] = []
            for _ in 0..<cols {
                row.append(Double.random(in: 0...1))
            }
            pattern.append(row)
        }
        return pattern
    }()
    
    var body: some View {
        Canvas { context, size in
            let pixelSize: CGFloat = 6 // Larger pixels = better performance
            let cols = min(Int(size.width / pixelSize), Self.noisePattern[0].count)
            let rows = min(Int(size.height / pixelSize), Self.noisePattern.count)
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let randomValue = Self.noisePattern[row][col]
                    let alpha = randomValue * intensity * 0.15
                    
                    let rect = CGRect(
                        x: CGFloat(col) * pixelSize,
                        y: CGFloat(row) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    
                    let grayValue = randomValue > 0.5 ? 1.0 : 0.0
                    context.fill(
                        Rectangle().path(in: rect),
                        with: .color(Color.white.opacity(grayValue * alpha))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .drawingGroup() // Use Metal rendering for better performance
    }
}

// MARK: - Pixelate View
struct PixelateView: View {
    var body: some View {
        Canvas { context, size in
            let pixelSize: CGFloat = 8
            let cols = Int(size.width / pixelSize) + 1
            let rows = Int(size.height / pixelSize) + 1
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let grayValue = Double.random(in: 0.2...0.4)
                    let rect = CGRect(
                        x: CGFloat(col) * pixelSize,
                        y: CGFloat(row) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(
                        Rectangle().path(in: rect),
                        with: .color(Color.gray.opacity(grayValue))
                    )
                }
            }
        }
    }
}