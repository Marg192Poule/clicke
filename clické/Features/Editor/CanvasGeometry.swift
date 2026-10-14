import CoreGraphics

/// Layout of the canvas, shared by the live canvas and the export so both are laid out identically.
///
/// Units:
/// - *Canvas points*: the canvas coordinate system (offsets, padding, blur radius…).
/// - *Layer points*: a layer's own points (its image's point size, corner radius, frame, shadow).
///   A layer is drawn at `layerScale(for:)` canvas points per layer point.
///
/// Export resolution:
/// - **Auto** (no preset): the canvas wraps the largest layer plus padding, and is exported at that
///   layer's native pixel density (2× for a Retina capture), so nothing gets downsampled.
/// - **Preset**: the canvas is `width × height` canvas points exported at 1×, i.e. exactly the
///   preset's pixel size; layers are scaled to fit inside the padding.
struct CanvasGeometry: Equatable {
    /// Canvas size, in canvas points.
    let canvasSize: CGSize
    /// Export pixels per canvas point.
    let pixelScale: CGFloat
    /// Exported image size, in whole pixels.
    let pixelSize: CGSize

    private let preset: SocialMediaPreset?
    private let padding: CGFloat

    /// Canvas used when there is no layer at all.
    private static let emptyCanvasSize = CGSize(width: 1200, height: 800)

    init(config: ScreenshotStyleConfig, items: [CanvasItem]) {
        let padding = CGFloat(max(config.padding, 0))
        self.padding = padding
        self.preset = config.canvasPreset

        let size: CGSize
        let scale: CGFloat
        if let preset {
            size = preset.size
            scale = 1
        } else if let reference = Self.referenceItem(in: items) {
            let framed = Self.rotatedBounds(of: reference.framedSize, degrees: reference.rotation)
            size = CGSize(width: framed.width + padding * 2, height: framed.height + padding * 2)
            scale = min(max(reference.image.pixelDensity, 1), 8)
        } else {
            size = Self.emptyCanvasSize
            scale = 1
        }

        // Snap to whole pixels so the export size is exact and deterministic.
        let pixels = CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
        self.pixelScale = scale
        self.pixelSize = pixels
        self.canvasSize = CGSize(width: pixels.width / scale, height: pixels.height / scale)
    }

    /// Whether the canvas has a fixed size (social preset) instead of wrapping the screenshot.
    var hasFixedSize: Bool { preset != nil }

    /// Canvas points per layer point.
    func layerScale(for item: CanvasItem) -> CGFloat {
        let userScale = CGFloat(max(item.scale, 1)) / 100
        guard let preset else { return userScale }

        let framed = Self.rotatedBounds(of: item.framedSize, degrees: item.rotation)
        guard framed.width > 0, framed.height > 0 else { return userScale }
        let available = CGSize(
            width: max(CGFloat(preset.width) - padding * 2, 1),
            height: max(CGFloat(preset.height) - padding * 2, 1)
        )
        return max(min(available.width / framed.width, available.height / framed.height), 0.01) * userScale
    }

    /// Size of the framed layer (before rotation), in canvas points.
    func layerSize(for item: CanvasItem) -> CGSize {
        let scale = layerScale(for: item)
        return CGSize(width: item.framedSize.width * scale, height: item.framedSize.height * scale)
    }

    /// Center of a layer in a view that draws the canvas at `scale` view points per canvas point.
    func center(of item: CanvasItem, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (canvasSize.width / 2 + item.offset.width) * scale,
            y: (canvasSize.height / 2 + item.offset.height) * scale
        )
    }

    /// "2400 × 1350 px"
    var pixelSizeDescription: String {
        "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px"
    }

    // MARK: Helpers

    /// The layer that defines an automatic canvas: the largest one.
    static func referenceItem(in items: [CanvasItem]) -> CanvasItem? {
        items.max { $0.framedSize.width * $0.framedSize.height < $1.framedSize.width * $1.framedSize.height }
    }

    /// Bounding box of a `size` rectangle rotated by `degrees`.
    static func rotatedBounds(of size: CGSize, degrees: Double) -> CGSize {
        let radians = degrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        return CGSize(
            width: size.width * cosine + size.height * sine,
            height: size.width * sine + size.height * cosine
        )
    }
}
