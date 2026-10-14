import SwiftUI
import QuartzCore

// The building blocks of the composition, shared by the live canvas and the exporter.
//
// Every view is laid out directly at its final size from a `scale` (view points per canvas
// point) instead of being laid out at full size and shrunk with `scaleEffect`. On screen that
// keeps textures, blurs and shadows proportional to what's actually displayed (fast); for
// export the same views are laid out in pixels. Since all lengths derive from the same canvas
// values, the export looks exactly like the canvas, only sharper.

// MARK: - Background

/// The canvas background: fill, color adjustments, blur and grain.
struct CanvasBackgroundView: View {
    let config: ScreenshotStyleConfig
    /// Background image, at any resolution (it's drawn aspect-fill).
    let image: CGImage?
    /// Size of the drawn canvas, in view points.
    let size: CGSize
    /// View points per canvas point.
    let scale: CGFloat
    /// Draws a checkerboard behind transparent backgrounds (canvas only, never exported).
    var showsCheckerboard = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if config.backgroundType == .transparent {
                if showsCheckerboard {
                    CanvasTextures.checkerboard(for: colorScheme)
                }
            } else {
                adjustedFill
                if config.effects.grain > 0 {
                    GrainOverlay(amount: config.effects.grain, scale: scale)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private var adjustedFill: some View {
        let effects = config.effects
        let fill = self.fill.modifier(ColorAdjustment(saturation: effects.saturation / 100, brightness: (effects.brightness - 100) / 100))
        if effects.blur > 0 {
            fill.blur(radius: effects.blur * scale, opaque: true)
        } else {
            fill
        }
    }

    @ViewBuilder
    private var fill: some View {
        switch config.backgroundType {
        case .transparent:
            Color.clear
        case .color:
            config.backgroundColor.color
        case .gradient:
            config.gradient.view(size: size)
        case .image:
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                // Shown for a split second while the wallpaper decodes.
                Color(white: 0.5)
            }
        }
    }
}

/// Saturation and brightness, skipped entirely at their neutral values (no filter pass per frame).
private struct ColorAdjustment: ViewModifier {
    /// 1 = unchanged.
    let saturation: Double
    /// 0 = unchanged.
    let brightness: Double

    func body(content: Content) -> some View {
        if saturation == 1 && brightness == 0 {
            content
        } else {
            content
                .saturation(saturation)
                .brightness(brightness)
        }
    }
}

// MARK: - Layer

/// A screenshot with its frame (mockup), corners, transforms and shadow, centered in its own frame.
/// The caller positions it.
struct LayerView: View {
    let item: CanvasItem
    let image: CGImage
    /// View points per layer point.
    let unit: CGFloat

    var body: some View {
        LayerFrameView(style: item.style, image: image, imageSize: item.image.pointSize, unit: unit)
            .contentShape(Rectangle())
            .modifier(LayerTransform(item: item))
            .modifier(LayerShadowModifier(shadow: item.style.shadow, unit: unit))
    }
}

/// 2D rotation then 3D tilt, shared by the layer and its selection outline so both line up.
struct LayerTransform: ViewModifier {
    let item: CanvasItem

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(item.rotation))
            .modifier(TiltEffect(angleX: item.rotationX, angleY: item.rotationY))
    }
}

/// A 3D tilt (around the horizontal then the vertical axis) with perspective, as one projection.
///
/// Unlike chained `rotation3DEffect`s, the perspective is computed once from the whole view's
/// size, so every part of a layer (image, frame, title bar) is projected identically, and the
/// result doesn't depend on the drawing scale (canvas and export match).
nonisolated struct TiltEffect: GeometryEffect {
    var angleX: Double
    var angleY: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angleX, angleY) }
        set {
            angleX = newValue.first
            angleY = newValue.second
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard angleX != 0 || angleY != 0, size.width > 0, size.height > 0 else { return ProjectionTransform() }
        var tilt = CATransform3DIdentity
        tilt.m34 = -1 / max(size.width, size.height)
        tilt = CATransform3DRotate(tilt, CGFloat(angleY) * .pi / 180, 0, 1, 0)
        tilt = CATransform3DRotate(tilt, CGFloat(angleX) * .pi / 180, 1, 0, 0)
        let toCenter = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
        let fromCenter = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        return ProjectionTransform(CATransform3DConcat(CATransform3DConcat(toCenter, tilt), fromCenter))
    }
}

/// Drop shadow, applied after the transforms so light always comes from above.
struct LayerShadowModifier: ViewModifier {
    let shadow: LayerShadow
    let unit: CGFloat

    func body(content: Content) -> some View {
        if shadow.isEnabled && shadow.opacity > 0 {
            content
                .compositingGroup() // one shadow for the whole layer, not one per element
                .shadow(
                    color: .black.opacity(shadow.opacity),
                    radius: shadow.radius * unit,
                    x: 0,
                    y: shadow.offsetY * unit
                )
        } else {
            content
        }
    }
}

// MARK: - Frame (Mockup)

/// The image inside its mockup frame (none, glass, border or macOS window).
///
/// Fills are shapes with explicit sizes: SwiftUI mis-projects flexible `Color` views under a 3D
/// projection, which would make the frame drift away from the image when the layer is tilted.
struct LayerFrameView: View {
    let style: LayerStyle
    let image: CGImage
    /// Image size, in layer points.
    let imageSize: CGSize
    /// View points per layer point.
    let unit: CGFloat

    var body: some View {
        let imageWidth = imageSize.width * unit
        let imageHeight = imageSize.height * unit
        let radius = style.cornerRadius * unit
        let frame = style.frameWidth * unit
        let framed = style.framedSize(for: imageSize)
        let outerWidth = framed.width * unit
        let outerHeight = framed.height * unit

        switch style.mockup {
        case .none:
            bitmap
                .frame(width: imageWidth, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

        case .border:
            ZStack {
                RoundedRectangle(cornerRadius: radius + frame, style: .continuous)
                    .fill(style.borderColor.color)
                    .frame(width: outerWidth, height: outerHeight)
                bitmap
                    .frame(width: imageWidth, height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .frame(width: outerWidth, height: outerHeight)

        case .glass:
            ZStack {
                GlassFrame(cornerRadius: radius + frame, unit: unit)
                    .frame(width: outerWidth, height: outerHeight)
                bitmap
                    .frame(width: imageWidth, height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.75 * unit)
                    .frame(width: imageWidth, height: imageHeight)
            }
            .frame(width: outerWidth, height: outerHeight)

        case .window:
            let isLight = style.windowAppearance == .light
            let titleBarHeight = LayerStyle.windowTitleBarHeight * unit
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(isLight ? Color.white : Color(white: 0.12))
                    .frame(width: outerWidth, height: outerHeight)
                WindowTitleBar(appearance: style.windowAppearance, unit: unit)
                    .frame(width: outerWidth, height: titleBarHeight)
                bitmap
                    .frame(width: imageWidth, height: imageHeight)
                    .offset(y: titleBarHeight)
            }
            .frame(width: outerWidth, height: outerHeight)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(isLight ? Color.black.opacity(0.14) : Color.white.opacity(0.16), lineWidth: 1 * unit)
                    .frame(width: outerWidth, height: outerHeight)
            )
        }
    }

    private var bitmap: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
    }
}

/// A frosted, translucent frame. Drawn with plain fills and strokes (not a system material,
/// which can't be rendered into an image), so it exports exactly as it looks.
private struct GlassFrame: View {
    let cornerRadius: CGFloat
    let unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.32), Color.white.opacity(0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.75), Color.white.opacity(0.15), Color.white.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5 * unit
            )
        }
    }
}

/// The title bar of the macOS window mockup, with traffic lights.
private struct WindowTitleBar: View {
    let appearance: WindowChromeAppearance
    let unit: CGFloat

    var body: some View {
        let isLight = appearance == .light
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(isLight ? Color(red: 0.925, green: 0.925, blue: 0.925) : Color(red: 0.17, green: 0.17, blue: 0.18))
                    .frame(width: proxy.size.width, height: proxy.size.height)

                HStack(spacing: 8 * unit) {
                    light(fill: RGBAColor(hex: "ff5f57"), stroke: RGBAColor(hex: "e0443e"))
                    light(fill: RGBAColor(hex: "febc2e"), stroke: RGBAColor(hex: "dea123"))
                    light(fill: RGBAColor(hex: "28c840"), stroke: RGBAColor(hex: "1aab29"))
                }
                .padding(.leading, 12 * unit)

                Rectangle()
                    .fill(isLight ? Color.black.opacity(0.1) : Color.black.opacity(0.45))
                    .frame(width: proxy.size.width, height: 1 * unit)
                    .offset(y: proxy.size.height / 2 - 0.5 * unit)
            }
        }
    }

    private func light(fill: RGBAColor, stroke: RGBAColor) -> some View {
        Circle()
            .fill(fill.color)
            .overlay(Circle().strokeBorder(stroke.color, lineWidth: 0.5 * unit))
            .frame(width: 12 * unit, height: 12 * unit)
    }
}

// MARK: - Export Composition

/// The complete, non-interactive composition, as exported.
struct ExportCanvasView: View {
    let config: ScreenshotStyleConfig
    let items: [CanvasItem]
    let geometry: CanvasGeometry
    let background: CGImage?
    /// View points per canvas point (the export lays the canvas out in pixels).
    let scale: CGFloat
    /// Whether to draw layers from their full-resolution bitmaps (export) or their previews (thumbnails).
    var usesFullResolution = true

    var body: some View {
        let size = CGSize(width: geometry.canvasSize.width * scale, height: geometry.canvasSize.height * scale)
        ZStack(alignment: .topLeading) {
            CanvasBackgroundView(config: config, image: background, size: size, scale: scale)

            ForEach(items.sorted { $0.zIndex < $1.zIndex }) { item in
                let unit = geometry.layerScale(for: item) * scale
                let width = item.image.pointSize.width * unit
                LayerView(
                    item: item,
                    image: usesFullResolution ? item.image.cgImage : item.image.bitmap(forDisplayPixelWidth: width),
                    unit: unit
                )
                .position(geometry.center(of: item, scale: scale))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
