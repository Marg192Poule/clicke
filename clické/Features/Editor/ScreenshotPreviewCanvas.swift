import SwiftUI
import AppKit

/// The main canvas view for previewing and editing screenshots.
struct ScreenshotPreviewCanvas: View {
    let items: [CanvasItem]
    let config: ScreenshotStyleConfig
    let selectedItemID: UUID?
    @Binding var isDragging: Bool
    var onItemOffsetChanged: ((UUID, CGSize) -> Void)? = nil
    var onItemSelected: ((UUID) -> Void)? = nil
    var isRendering: Bool = false
    var preloadedBackgroundImage: NSImage? = nil

    private let canvasCornerRadius: CGFloat = 24
    @State private var loadedBackgroundImage: NSImage? = nil
    @State private var currentLoadingURL: URL? = nil

    /// Reference image used for canvas sizing (largest item)
    private var referenceImage: NSImage {
        items.max(by: { $0.image.size.width * $0.image.size.height < $1.image.size.width * $1.image.size.height })?.image ?? NSImage()
    }

    var body: some View {
        ZStack {
            // Background with unified blur (except transparent)
            if config.backgroundType == .transparent {
                backgroundView
                    .frame(width: totalWidth, height: totalHeight)
            } else {
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

                // Noise overlay (skip during export)
                if config.gradientConfig.noiseAmount > 0 && !isRendering {
                    NoiseTextureView(intensity: config.gradientConfig.noiseAmount / 100, size: CGSize(width: totalWidth, height: totalHeight))
                }
            }

            // Render each canvas item sorted by zIndex
            ForEach(items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                CanvasItemView(
                    item: item,
                    config: config,
                    isSelected: !isRendering && item.id == selectedItemID,
                    isDragging: $isDragging,
                    onOffsetChanged: { newOffset in
                        onItemOffsetChanged?(item.id, newOffset)
                    },
                    onSelected: {
                        onItemSelected?(item.id)
                    }
                )
            }

            // Text overlays
            ForEach(config.textOverlays) { overlay in
                textOverlayView(overlay)
            }
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

    // MARK: - Dimensions

    private var totalWidth: CGFloat {
        if let preset = config.selectedSocialPreset {
            return CGFloat(preset.width)
        }
        return referenceImage.size.width + config.padding * 2
    }

    private var totalHeight: CGFloat {
        if let preset = config.selectedSocialPreset {
            return CGFloat(preset.height)
        }
        return referenceImage.size.height + config.padding * 2
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
            } else {
                colorBackground
            }
        }
        .colorAdjustments(
            saturation: config.gradientConfig.saturation / 100,
            brightness: (config.gradientConfig.brightness - 100) / 100
        )
        .onChange(of: config.backgroundImageURL?.absoluteString) { _, newValue in
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

    private func loadBackgroundImageAsync(from url: URL) {
        currentLoadingURL = url

        Task {
            let image = await ImageLoadingService.shared.loadImage(from: url, maxDimension: 4096)

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
}

// MARK: - Canvas Item View

/// Renders a single image item on the canvas with its own transforms and drag gesture.
struct CanvasItemView: View {
    let item: CanvasItem
    let config: ScreenshotStyleConfig
    let isSelected: Bool
    @Binding var isDragging: Bool
    var onOffsetChanged: ((CGSize) -> Void)? = nil
    var onSelected: (() -> Void)? = nil

    @State private var dragOffset: CGSize = .zero

    private var socialPresetImageScale: CGFloat {
        guard let preset = config.selectedSocialPreset else { return 1.0 }

        let presetWidth = CGFloat(preset.width)
        let presetHeight = CGFloat(preset.height)
        let imageWidth = item.image.size.width + config.padding * 2
        let imageHeight = item.image.size.height + config.padding * 2

        let availableWidth = presetWidth * 0.8
        let availableHeight = presetHeight * 0.8

        let scaleX = availableWidth / imageWidth
        let scaleY = availableHeight / imageHeight

        return min(scaleX, scaleY) * (item.imageScale / 100)
    }

    var body: some View {
        let content = Group {
            if config.selectedSocialPreset != nil {
                screenshotContent.scaleEffect(socialPresetImageScale)
            } else {
                screenshotContent.scaleEffect(item.imageScale / 100)
            }
        }

        content
            .rotationEffect(.degrees(item.rotation))
            .rotation3DEffect(
                .degrees(item.rotationX),
                axis: (x: 1, y: 0, z: 0),
                perspective: (item.rotationX != 0 || item.rotationY != 0) ? 1.0 : 0
            )
            .rotation3DEffect(
                .degrees(item.rotationY),
                axis: (x: 0, y: 1, z: 0),
                perspective: (item.rotationX != 0 || item.rotationY != 0) ? 1.0 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: item.transformHash)
            .offset(CGSize(
                width: item.offset.width + dragOffset.width,
                height: item.offset.height + dragOffset.height
            ))
            .allowsHitTesting(isSelected)
            .highPriorityGesture(dragGesture)
    }

    @ViewBuilder
    private var screenshotContent: some View {
        if item.showMockup {
            styledScreenshot
        } else {
            Image(nsImage: item.image)
                .clipShape(RoundedRectangle(cornerRadius: item.borderRadius))
        }
    }

    @ViewBuilder
    private var styledScreenshot: some View {
        switch item.mockupStyle {
        case .defaultStyle:
            Image(nsImage: item.image)
                .clipShape(RoundedRectangle(cornerRadius: item.borderRadius))
        case .glassEffect:
            glassEffectMockup
        case .border:
            borderMockup
        }
    }

    private var glassEffectMockup: some View {
        let borderWidth = item.mockupBorderSize * 3
        let cornerRadius = item.borderRadius + borderWidth * 0.5

        return Image(nsImage: item.image)
            .clipShape(RoundedRectangle(cornerRadius: item.borderRadius))
            .padding(borderWidth)
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var borderMockup: some View {
        let borderWidth = item.mockupBorderSize * 3

        return Image(nsImage: item.image)
            .clipShape(RoundedRectangle(cornerRadius: item.borderRadius))
            .padding(borderWidth)
            .background {
                RoundedRectangle(cornerRadius: item.borderRadius + borderWidth * 0.5)
                    .fill(item.borderColor)
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if !isDragging {
                    onSelected?()
                }
                isDragging = true
                dragOffset = value.translation
            }
            .onEnded { value in
                let newOffset = CGSize(
                    width: item.offset.width + value.translation.width,
                    height: item.offset.height + value.translation.height
                )
                onOffsetChanged?(newOffset)
                dragOffset = .zero
                isDragging = false
            }
    }
}

// MARK: - Checkerboard View (GPU-accelerated)

/// A GPU-accelerated checkerboard pattern for transparent backgrounds.
struct CheckerboardView: View {
    let squareSize: CGFloat = 12

    var body: some View {
        CheckerboardShaderView(squareSize: squareSize)
    }
}

// MARK: - Pixelate View (GPU-accelerated)

/// A GPU-accelerated pixelation effect view.
struct PixelateView: View {
    var body: some View {
        PixelateShaderView(pixelSize: 8)
    }
}
