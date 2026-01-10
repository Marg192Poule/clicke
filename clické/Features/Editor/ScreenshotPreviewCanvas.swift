import SwiftUI
import AppKit

struct ScreenshotPreviewCanvas: View {
    let image: NSImage
    let config: ScreenshotStyleConfig
    @Binding var isDragging: Bool
    var onScreenshotOffsetChanged: ((CGSize) -> Void)? = nil
    var isRendering: Bool = false
    var preloadedBackgroundImage: NSImage? = nil
    
    private let canvasCornerRadius: CGFloat = 24
    @State private var dragOffset: CGSize = .zero
    @State private var loadedBackgroundImage: NSImage? = nil
    @State private var currentLoadingURL: URL? = nil
    
    var body: some View {
        ZStack {
            // Background with unified blur (except transparent)
            if config.backgroundType == .transparent {
                backgroundView
                    .frame(width: totalWidth, height: totalHeight)
            } else {
                // Only apply drawingGroup if blur > 0 (otherwise degraded quality)
                if config.gradientConfig.blurAmount > 0 {
                    backgroundView
                        .frame(width: totalWidth, height: totalHeight)
                        .clipped()
                        .blur(radius: config.gradientConfig.blurAmount)
                        .drawingGroup(opaque: true, colorMode: .linear)
                } else {
                    backgroundView
                        .frame(width: totalWidth, height: totalHeight)
                        .clipped()
                }
                
                // Noise overlay (skip during export - Metal shaders don't work with ImageRenderer)
                if config.gradientConfig.noiseAmount > 0 && !isRendering {
                    NoiseTextureView(intensity: config.gradientConfig.noiseAmount / 100, size: CGSize(width: totalWidth, height: totalHeight))
                }
            }
            
            // Shadow scene underlay
            if config.shadowSceneMode == .underlay && config.selectedShadowScene != nil {
                shadowSceneOverlay
                    .opacity(config.shadowSceneOpacity / 100)
            }
            
            // Screenshot with transforms
            screenshotLayer
            
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
        }
        .frame(width: totalWidth, height: totalHeight)
        .clipShape(RoundedRectangle(cornerRadius: canvasCornerRadius))
    }
    
    // MARK: - Screenshot Layer (consolidated transforms)
    @ViewBuilder
    private var screenshotLayer: some View {
        let content = Group {
            if config.selectedSocialPreset != nil {
                screenshotContent.scaleEffect(socialPresetImageScale)
            } else {
                screenshotContent.scaleEffect(config.imageScale / 100)
            }
        }
        
        content
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
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: config.transformHash)
            .offset(CGSize(
                width: config.screenshotOffset.width + dragOffset.width,
                height: config.screenshotOffset.height + dragOffset.height
            ))
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture)
    }
    
    private var dragGesture: some Gesture {
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
    
    // MARK: - Shadow Scene Overlay
    @ViewBuilder
    private var shadowSceneOverlay: some View {
        if let scene = config.selectedShadowScene {
            LinearGradient(
                colors: scene.colors.map { $0.opacity(0.3) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .mask {
                Canvas { context, size in
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
        if let preset = config.selectedSocialPreset {
            return CGFloat(preset.width)
        }
        return image.size.width + config.padding * 2
    }
    
    private var totalHeight: CGFloat {
        if let preset = config.selectedSocialPreset {
            return CGFloat(preset.height)
        }
        return image.size.height + config.padding * 2
    }
    
    private var socialPresetImageScale: CGFloat {
        guard let preset = config.selectedSocialPreset else { return 1.0 }
        
        let presetWidth = CGFloat(preset.width)
        let presetHeight = CGFloat(preset.height)
        let imageWidth = image.size.width + config.padding * 2
        let imageHeight = image.size.height + config.padding * 2
        
        // Use 80% of preset size as available area for better default fit
        let availableWidth = presetWidth * 0.8
        let availableHeight = presetHeight * 0.8
        
        let scaleX = availableWidth / imageWidth
        let scaleY = availableHeight / imageHeight
        
        // Allow scaling up (no 1.0 limit) so smaller images fill the format better
        return min(scaleX, scaleY) * (config.imageScale / 100)
    }
    
    // MARK: - Screenshot Content
    @ViewBuilder
    private var screenshotContent: some View {
        if config.showMockup {
            styledScreenshot
        } else {
            Image(nsImage: image)
                .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
        }
    }
    
    // MARK: - Background View
    @ViewBuilder
    private var backgroundView: some View {
        Group {
            switch config.backgroundType {
            case .transparent:
                if isRendering {
                    Color.clear
                } else {
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
        .colorAdjustments(
            saturation: isRendering ? 1.0 : config.gradientConfig.saturation / 100,
            brightness: isRendering ? 0.0 : (config.gradientConfig.brightness - 100) / 100
        )
    }
    
    @ViewBuilder
    private var imageBackground: some View {
        Group {
            if config.backgroundImageURL != nil {
                if let preloaded = preloadedBackgroundImage {
                    Image(nsImage: preloaded)
                        .interpolation(.high)
                        .antialiased(true)
                        .resizable()
                        .scaledToFill()
                        .frame(width: totalWidth, height: totalHeight)
                } else if let cachedImage = loadedBackgroundImage {
                    Image(nsImage: cachedImage)
                        .interpolation(.high)
                        .antialiased(true)
                        .resizable()
                        .scaledToFill()
                        .frame(width: totalWidth, height: totalHeight)
                } else {
                    colorBackground
                }
            } else if let scene = config.selectedShadowScene {
                sceneBackground(scene)
            } else {
                colorBackground
            }
        }
        .colorAdjustments(
            saturation: config.gradientConfig.saturation / 100,
            brightness: (config.gradientConfig.brightness - 100) / 100
        )
        .onChange(of: config.backgroundImageURL?.absoluteString) { _, newValue in
            // Do NOT set loadedBackgroundImage to nil - keep old background during loading
            if let urlString = newValue, let newURL = URL(string: urlString) {
                loadBackgroundImageAsync(from: newURL)
            }
        }
        .onAppear {
            if let url = config.backgroundImageURL, loadedBackgroundImage == nil {
                loadBackgroundImageAsync(from: url)
            }
        }
    }
    
    /// Loads background image asynchronously via centralized service
    private func loadBackgroundImageAsync(from url: URL) {
        currentLoadingURL = url
        
        Task {
            // Limit to 4096px max to avoid IOSurface errors (GPU limit)
            // 4096x4096 = 64 million pixels, sufficient for 5K displays
            let image = await ImageLoadingService.shared.loadImage(from: url, maxDimension: 4096)
            
            // Verify URL hasn't changed during loading
            await MainActor.run {
                if currentLoadingURL == url {
                    loadedBackgroundImage = image
                }
            }
        }
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
        if isRendering {
            LinearGradient(colors: scene.colors, startPoint: .top, endPoint: .bottom)
        } else {
            LinearGradient(colors: scene.colors, startPoint: .top, endPoint: .bottom)
                .noiseOverlay(intensity: 0.15)
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
        let borderWidth = config.mockupBorderSize * 3
        let cornerRadius = config.borderRadius + borderWidth * 0.5
        
        return Image(nsImage: image)
            .clipShape(RoundedRectangle(cornerRadius: config.borderRadius))
            .padding(borderWidth)
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    private var borderMockup: some View {
        let borderWidth = config.mockupBorderSize * 3
        
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
        CheckerboardShaderView(squareSize: squareSize)
    }
}

// MARK: - Noise View (GPU-accelerated)
struct NoiseView: View {
    let intensity: Double
    
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .noiseOverlay(intensity: intensity)
            .allowsHitTesting(false)
    }
}

// MARK: - Pixelate View (GPU-accelerated)
struct PixelateView: View {
    var body: some View {
        PixelateShaderView(pixelSize: 8)
    }
}
