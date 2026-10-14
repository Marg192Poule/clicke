import AppKit
import ImageIO

// MARK: - Imported Image

/// A bitmap ready to become a canvas layer: decoded within the editor's limits, with a sane point size.
///
/// `@unchecked Sendable`: `CGImage` is immutable and thread-safe.
nonisolated struct ImportedImage: @unchecked Sendable {
    let cgImage: CGImage
    /// Size in points: pixels / pixel density, the density being clamped to `ImageImport.densityRange`.
    let pointSize: CGSize
}

nonisolated enum ImageImportError: LocalizedError {
    case tooLarge
    case unreadable

    var errorDescription: String? {
        switch self {
        case .tooLarge: String(localized: "This image is too large to edit.")
        case .unreadable: String(localized: "The file isn’t an image Clické can open.")
        }
    }
}

// MARK: - Image Import

/// Turns image files, image data and `NSImage`s into layer bitmaps without ever decoding an
/// unbounded image: the pixel size and DPI are read first (headers / representations), then the
/// image is decoded at most `maxPixelSize` pixels wide, and absurd sizes are refused.
nonisolated enum ImageImport {
    /// Longest side of a layer bitmap, in pixels. Larger images are downsampled while decoding.
    static let maxPixelSize = 16_384
    /// Area limit of a layer bitmap (≈ 800 MB of RGBA pixels).
    static let maxPixelCount = 200_000_000
    /// Images larger than this are refused: even a downsampled decode would take seconds and gigabytes.
    static let maxSourcePixelCount = 500_000_000
    static let maxSourcePixelSize = 100_000
    /// Longest side of a rasterized vector image (PDF, SVG…), in pixels.
    static let maxVectorPixelSize = 4096
    /// Pixels per point taken from the image's DPI: below 72 DPI counts as 72, above 288 as 288.
    static let densityRange: ClosedRange<CGFloat> = 1...4

    // MARK: Files and Data

    /// Decodes an image file. Synchronous: call it off the main actor.
    static func load(contentsOf url: URL) throws -> ImportedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageImportError.unreadable
        }
        return try load(from: source)
    }

    /// Decodes encoded image data (PNG, JPEG, HEIC, TIFF…). Synchronous: call it off the main actor.
    static func load(data: Data) throws -> ImportedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageImportError.unreadable
        }
        return try load(from: source)
    }

    /// Whether ImageIO can decode `url` (vector formats such as PDF can't be, and go through `NSImage`).
    static func canDecode(contentsOf url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceGetType(source) != nil
    }

    private static func load(from source: CGImageSource) throws -> ImportedImage {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else {
            throw ImageImportError.unreadable
        }
        try checkSourceSize(width: width, height: height)

        // Orientations 5–8 swap width and height (the decoded image is rotated upright).
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let pixels = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let density = clampedDensity(dpi / 72)
        let pointSize = CGSize(width: pixels.width / density, height: pixels.height / density)

        // The thumbnail API decodes straight to the bounded size and applies the EXIF orientation.
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: boundedLongestSide(for: pixels),
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width > 0, image.height > 0 else {
            throw ImageImportError.unreadable
        }
        return ImportedImage(cgImage: image, pointSize: fittedPointSize(pointSize, for: image))
    }

    // MARK: NSImage

    /// What it takes to turn an `NSImage` into a layer.
    enum Preparation {
        /// Usable as is.
        case ready(ImportedImage)
        /// A large bitmap: pass it to `decode(_:maxPixelSize:)`, off the main actor, which also
        /// downsamples it if it's above the layer limits.
        case needsDecoding(ImportedImage, maxPixelSize: Int)
    }

    /// Bitmaps above this many pixels are decoded off the main actor even within the limits: a
    /// file-backed `NSImage` would otherwise decode on the main actor when first drawn. Screen
    /// captures (≤ 33 MP for an 8K display) stay below it, so they open without a delay.
    static let backgroundDecodingPixelCount = 50_000_000

    /// Checks an `NSImage` from its representations (no decoding) and gets its bitmap.
    /// Vector images are rasterized here, at a bounded size.
    @MainActor
    static func prepare(_ image: NSImage) throws -> Preparation {
        let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        if let bitmap = bitmaps.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
           bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 {
            try checkSourceSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            let pixels = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            // The image size carries the DPI: a 144 DPI capture is half its pixel size in points.
            let size = image.size.width > 0 ? image.size : bitmap.size
            let density = clampedDensity(size.width > 0 ? pixels.width / size.width : 1)
            // `cgImage` doesn't decode: a file-backed bitmap stays lazy until it's drawn.
            guard let cgImage = bitmap.cgImage else { throw ImageImportError.unreadable }
            let full = ImportedImage(cgImage: cgImage, pointSize: CGSize(width: pixels.width / density, height: pixels.height / density))
            let limit = boundedLongestSide(for: pixels)
            let isLarge = limit < Int(max(pixels.width, pixels.height))
                || bitmap.pixelsWide * bitmap.pixelsHigh > backgroundDecodingPixelCount
            return isLarge ? .needsDecoding(full, maxPixelSize: limit) : .ready(full)
        }
        return .ready(try rasterizeVector(image))
    }

    /// Decodes a bitmap that `prepare(_:)` found large, downsampled to `maxPixelSize` if needed.
    /// Synchronous: call it off the main actor.
    static func decode(_ image: ImportedImage, maxPixelSize: Int) -> ImportedImage {
        let source = image.cgImage
        let decoded = max(source.width, source.height) > maxPixelSize
            ? ImageLoadingService.downsampleSync(source, maxPixelSize: maxPixelSize)
            : redrawn(source)
        return ImportedImage(cgImage: decoded, pointSize: fittedPointSize(image.pointSize, for: decoded))
    }

    /// The image drawn into a bitmap of its own size: forces a lazily decoded image to decode now.
    private static func redrawn(_ image: CGImage) -> CGImage {
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    /// Rasterizes a vector image (or any non-bitmap representation) at 2× when it fits,
    /// never more than `maxVectorPixelSize` pixels wide.
    @MainActor
    private static func rasterizeVector(_ image: NSImage) throws -> ImportedImage {
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw ImageImportError.unreadable
        }
        let longest = max(size.width, size.height)
        let limit = CGFloat(maxVectorPixelSize)
        let density = min(max(limit / longest, 1), 2)
        let scale = min(density, limit / longest) // pixels per point; below `density` for huge images
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw ImageImportError.unreadable }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else { throw ImageImportError.unreadable }
        return ImportedImage(cgImage: cgImage, pointSize: CGSize(width: CGFloat(width) / density, height: CGFloat(height) / density))
    }

    // MARK: Limits

    private static func checkSourceSize(width: Int, height: Int) throws {
        guard max(width, height) <= maxSourcePixelSize, width * height <= maxSourcePixelCount else {
            throw ImageImportError.tooLarge
        }
    }

    /// The longest side to decode an image of `pixels` at, within `maxPixelSize` and `maxPixelCount`.
    private static func boundedLongestSide(for pixels: CGSize) -> Int {
        let longest = max(pixels.width, pixels.height)
        let areaFactor = min(sqrt(CGFloat(maxPixelCount) / max(pixels.width * pixels.height, 1)), 1)
        return max(1, Int(min(longest * areaFactor, CGFloat(maxPixelSize)).rounded(.down)))
    }

    private static func clampedDensity(_ density: CGFloat) -> CGFloat {
        guard density.isFinite else { return 1 }
        return min(max(density, densityRange.lowerBound), densityRange.upperBound)
    }

    /// The point size of `image`, a possibly downsampled decode of an image of `pointSize` points:
    /// it keeps that size unless the density would fall below 1 pixel per point.
    private static func fittedPointSize(_ pointSize: CGSize, for image: CGImage) -> CGSize {
        let pixels = CGSize(width: image.width, height: image.height)
        let density = clampedDensity(max(pixels.width, pixels.height) / max(pointSize.width, pointSize.height, 1))
        return CGSize(width: pixels.width / density, height: pixels.height / density)
    }
}
