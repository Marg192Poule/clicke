import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os

/// Bakes redaction regions into image pixels with Core Image.
///
/// Region rectangles are expressed in the full-resolution pixel space of the source image,
/// with the origin at the top-left. Everything here is thread-safe and meant to run off the
/// main actor.
nonisolated enum ImageRedactor {

    // MARK: - Types

    /// A downscaled copy of the source image, used to render the live preview quickly.
    struct WorkingCopy: Sendable {
        let image: CGImage
        /// Working-copy pixels per source pixel (at most 1).
        let scale: CGFloat
        /// Source pixels per point, so effects look the same at any display resolution.
        let pixelsPerPoint: CGFloat

        var size: CGSize { CGSize(width: image.width, height: image.height) }
    }

    /// Identifies a rendered preview patch. A patch is reused as long as its key is unchanged.
    struct PatchKey: Equatable, Sendable {
        /// Rectangle in working-copy pixel space (top-left origin, integral).
        let rect: CGRect
        let style: RedactionStyle
        let strength: Double
    }

    /// A preview patch to render for a region.
    struct PatchRequest: Sendable {
        let id: UUID
        let key: PatchKey
    }

    /// The rendered preview of one region's effect.
    struct PreviewPatch: Sendable {
        let id: UUID
        let key: PatchKey
        let image: CGImage
        /// Area covered by `image`, in source pixel space.
        let sourceRect: CGRect
    }

    // MARK: - Shared State

    /// Core Image contexts are thread-safe; one is shared by all renders.
    private static let context = CIContext(options: [.cacheIntermediates: false, .name: "Redaction"])
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "clicke", category: "Redaction")

    // MARK: - Final Render

    /// Returns a copy of `image` with `regions` baked into its pixels, rendered off the main actor.
    @concurrent
    static func redacting(_ image: CGImage, regions: [RedactionRegion], pixelsPerPoint: CGFloat) async -> CGImage? {
        redact(image, regions: regions, pixelsPerPoint: pixelsPerPoint)
    }

    /// Returns a copy of `image` with `regions` baked into its pixels, at full resolution.
    ///
    /// Pixels outside the regions are copied untouched. If an effect fails to render, its
    /// region is filled with black rather than left readable.
    static func redact(_ image: CGImage, regions: [RedactionRegion], pixelsPerPoint: CGFloat) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let canvas = makeBitmapContext(width: width, height: height, colorSpace: renderColorSpace(for: image)) else {
            logger.error("Couldn't create a \(width)×\(height) bitmap context")
            return nil
        }

        let imageSize = CGSize(width: width, height: height)
        canvas.draw(image, in: CGRect(origin: .zero, size: imageSize))
        // Patches replace pixels outright, so nothing underneath can show through transparency.
        canvas.setBlendMode(.copy)
        canvas.interpolationQuality = .none

        let source = CIImage(cgImage: image)
        for region in RedactionRegion.compositingOrder(regions) {
            guard let rect = pixelRect(region.rect, in: imageSize) else { continue }
            let drawRect = flipped(rect, height: imageSize.height)

            if region.style != .solid {
                if let patch = renderPatch(
                    style: region.style,
                    strength: region.strength,
                    rect: rect,
                    source: source,
                    pixelsPerPoint: pixelsPerPoint,
                    scale: 1,
                    colorSpace: canvas.colorSpace
                ) {
                    canvas.draw(patch, in: drawRect)
                    continue
                }
                logger.error("Couldn't render a \(region.style.rawValue, privacy: .public) effect; filling the area instead")
            }

            canvas.setFillColor(region.style == .solid ? region.fill.cgColor : RedactionFill.black.cgColor)
            canvas.fill(drawRect)
        }

        return canvas.makeImage()
    }

    // MARK: - Preview

    /// Downscales `image` so its longest side fits in `maxDimension` pixels, off the main actor.
    @concurrent
    static func makeWorkingCopy(of image: CGImage, maxDimension: CGFloat, pixelsPerPoint: CGFloat) async -> WorkingCopy {
        let original = WorkingCopy(image: image, scale: 1, pixelsPerPoint: pixelsPerPoint)
        let longestSide = CGFloat(max(image.width, image.height))
        guard longestSide > maxDimension else { return original }

        let scale = maxDimension / longestSide
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = makeBitmapContext(width: width, height: height, colorSpace: renderColorSpace(for: image)) else {
            return original
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return original }
        return WorkingCopy(image: scaled, scale: CGFloat(width) / CGFloat(image.width), pixelsPerPoint: pixelsPerPoint)
    }

    /// The preview patch key for `region`, or nil when the region needs no rendered patch.
    static func patchKey(for region: RedactionRegion, in copy: WorkingCopy) -> PatchKey? {
        guard region.style != .solid else { return nil }
        let scaled = CGRect(
            x: region.rect.minX * copy.scale,
            y: region.rect.minY * copy.scale,
            width: region.rect.width * copy.scale,
            height: region.rect.height * copy.scale
        )
        guard let rect = pixelRect(scaled, in: copy.size) else { return nil }
        return PatchKey(rect: rect, style: region.style, strength: region.strength)
    }

    /// Renders the requested preview patches from the working copy, off the main actor.
    @concurrent
    static func renderPreviewPatches(_ requests: [PatchRequest], in copy: WorkingCopy) async -> [PreviewPatch] {
        let source = CIImage(cgImage: copy.image)
        let colorSpace = renderColorSpace(for: copy.image)
        return requests.compactMap { request in
            guard let image = renderPatch(
                style: request.key.style,
                strength: request.key.strength,
                rect: request.key.rect,
                source: source,
                pixelsPerPoint: copy.pixelsPerPoint,
                scale: copy.scale,
                colorSpace: colorSpace
            ) else { return nil }

            let rect = request.key.rect
            let sourceRect = CGRect(
                x: rect.minX / copy.scale,
                y: rect.minY / copy.scale,
                width: rect.width / copy.scale,
                height: rect.height / copy.scale
            )
            return PreviewPatch(id: request.id, key: request.key, image: image, sourceRect: sourceRect)
        }
    }

    // MARK: - Effect Parameters

    /// Pixelation block size, in pixels of the image being rendered.
    ///
    /// - Parameters:
    ///   - rect: The region, in pixels of the image being rendered.
    ///   - scale: Rendered pixels per source pixel (1 for the final render).
    static func blockSize(for rect: CGRect, strength: Double, pixelsPerPoint: CGFloat, scale: CGFloat) -> CGFloat {
        let strength = CGFloat(min(max(strength, 0), 1))
        // At least 10 px and 4–12 pt, so text glyphs collapse into a few blocks…
        let minimum = max(10, (4 + 8 * strength) * pixelsPerPoint) * scale
        // …and 1.5–3 % of the region's short side, so large areas stay coarse too.
        let relative = min(rect.width, rect.height) * (0.015 + 0.015 * strength)
        return max(minimum, relative, 1)
    }

    /// Gaussian blur sigma, in pixels of the image being rendered.
    static func blurRadius(for rect: CGRect, strength: Double, pixelsPerPoint: CGFloat, scale: CGFloat) -> CGFloat {
        let strength = CGFloat(min(max(strength, 0), 1))
        // 4–13 pt: well past the stroke width of UI text even at the lowest setting.
        let minimum = (4 + 9 * strength) * pixelsPerPoint * scale
        let relative = min(rect.width, rect.height) * (0.04 + 0.08 * strength)
        let maximum = 150 * pixelsPerPoint * scale
        return max(min(max(minimum, relative), maximum), 1)
    }

    // MARK: - Helpers

    /// Integral rectangle (expanded outward) clamped to an image of `size`, or nil if empty.
    static func pixelRect(_ rect: CGRect, in size: CGSize) -> CGRect? {
        let clamped = rect.standardized.integral.intersection(CGRect(origin: .zero, size: size))
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return clamped
    }

    /// Converts a top-left-origin rectangle to Core Graphics / Core Image bottom-left coordinates.
    private static func flipped(_ rect: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Renders one region's effect, cropped to `rect` (top-left origin, integral).
    private static func renderPatch(
        style: RedactionStyle,
        strength: Double,
        rect: CGRect,
        source: CIImage,
        pixelsPerPoint: CGFloat,
        scale: CGFloat,
        colorSpace: CGColorSpace?
    ) -> CGImage? {
        let ciRect = flipped(rect, height: source.extent.height)
        // Clamping the cropped area keeps the effect from sampling pixels outside the region.
        let isolated = source.cropped(to: ciRect).clampedToExtent()

        let output: CIImage?
        switch style {
        case .pixelate:
            let block = blockSize(for: rect, strength: strength, pixelsPerPoint: pixelsPerPoint, scale: scale)
            // CIPixellate samples one pixel per block; box-averaging first gives each block the
            // mean color of the pixels it covers, like a classic mosaic.
            let average = CIFilter.boxBlur()
            average.inputImage = isolated
            average.radius = Float(block / 2)
            let pixellate = CIFilter.pixellate()
            pixellate.inputImage = average.outputImage
            pixellate.scale = Float(block)
            // Align the block grid with the region's top-left corner.
            pixellate.center = CGPoint(x: ciRect.minX, y: ciRect.maxY)
            output = pixellate.outputImage
        case .blur:
            let sigma = blurRadius(for: rect, strength: strength, pixelsPerPoint: pixelsPerPoint, scale: scale)
            output = isolated.applyingGaussianBlur(sigma: Double(sigma))
        case .solid:
            output = nil
        }

        guard let output else { return nil }
        let space = colorSpace ?? renderColorSpace(for: nil)
        return context.createCGImage(output.cropped(to: ciRect), from: ciRect, format: .RGBA8, colorSpace: space)
    }

    /// The source's RGB color space when it can be rendered into, sRGB otherwise.
    private static func renderColorSpace(for image: CGImage?) -> CGColorSpace {
        if let space = image?.colorSpace, space.model == .rgb, space.supportsOutput {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    private static func makeBitmapContext(width: Int, height: Int, colorSpace: CGColorSpace) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
