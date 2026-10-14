import AppKit
import ImageIO

// MARK: - Image Cache

/// A bounded, thread-safe cache of decoded images (backed by `NSCache`, which also evicts under memory pressure).
nonisolated final class ImageCache: @unchecked Sendable {
    private final class Box {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let cache = NSCache<NSString, Box>()

    /// - Parameter totalCostLimit: Maximum decoded size kept in memory, in bytes.
    init(totalCostLimit: Int) {
        cache.totalCostLimit = totalCostLimit
    }

    subscript(key: String) -> CGImage? {
        get { cache.object(forKey: key as NSString)?.image }
        set {
            if let newValue {
                cache.setObject(Box(newValue), forKey: key as NSString, cost: newValue.bytesPerRow * newValue.height)
            } else {
                cache.removeObject(forKey: key as NSString)
            }
        }
    }
}

// MARK: - Image Loading Service

/// Decodes and downsamples images with ImageIO / Core Graphics.
///
/// Everything heavy is `@concurrent`, so it never runs on the main actor. ImageIO decodes
/// JPEG and HEIC straight to the requested size, which is much faster (and lighter) than
/// decoding the full image and resizing it.
nonisolated enum ImageLoadingService {
    /// Decoded background images at the sizes the editor asked for (canvas previews, exports).
    static let cache = ImageCache(totalCostLimit: 192 * 1024 * 1024)

    // MARK: Metadata

    /// Pixel size of an image file, read from its header (no decoding). Accounts for EXIF orientation.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return pixelSize(of: source)
    }

    private static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // Orientations 5–8 swap width and height.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation >= 5 {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }

    // MARK: Loading

    /// Decodes an image file so that its longest side is at most `maxPixelSize` (`nil` = full size).
    @concurrent
    static func loadImage(at url: URL, maxPixelSize: Int? = nil) async -> CGImage? {
        loadImageSync(at: url, maxPixelSize: maxPixelSize)
    }

    /// Decodes an image just large enough to cover `targetSize` pixels aspect-fill (cached).
    /// The requested size is rounded up to a 256 px step so small size changes reuse the cache.
    @concurrent
    static func cachedImage(at url: URL, covering targetSize: CGSize) async -> CGImage? {
        cachedImageSync(at: url, covering: targetSize)
    }

    /// Synchronous variant of `cachedImage(at:covering:)`.
    static func cachedImageSync(at url: URL, covering targetSize: CGSize) -> CGImage? {
        let sourceSize = pixelSize(of: url) ?? targetSize
        let needed = coverPixelSize(source: sourceSize, target: targetSize)
        let nativeMax = Int(max(sourceSize.width, sourceSize.height))
        let step = 256
        let bucket = min(((needed + step - 1) / step) * step, nativeMax)
        let key = "\(url.path)#\(bucket)"
        if let cached = cache[key] { return cached }
        let image = loadImageSync(at: url, maxPixelSize: bucket)
        if let image { cache[key] = image }
        return image
    }

    /// Synchronous decoding. Only call it off the main actor, or for a small image.
    static func loadImageSync(at url: URL, maxPixelSize: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let nativeSize = pixelSize(of: source) ?? CGSize(width: 16_384, height: 16_384)
        let nativeMax = Int(max(nativeSize.width, nativeSize.height))
        let target = min(maxPixelSize ?? nativeMax, nativeMax)

        // The thumbnail API applies the EXIF orientation and decodes at the target size directly.
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(target, 1),
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The `maxPixelSize` to request so that an image of `sourceSize` pixels covers `targetSize`
    /// pixels when drawn aspect-fill (the background behaviour).
    static func coverPixelSize(source sourceSize: CGSize, target targetSize: CGSize) -> Int {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return Int(max(targetSize.width, targetSize.height)) }
        let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        return Int((max(sourceSize.width, sourceSize.height) * min(scale, 1)).rounded(.up))
    }

    // MARK: Resizing

    /// Returns a copy of `image` whose longest side is at most `maxPixelSize` (or `image` itself if already smaller).
    @concurrent
    static func downsample(_ image: CGImage, maxPixelSize: Int) async -> CGImage {
        downsampleSync(image, maxPixelSize: maxPixelSize)
    }

    static func downsampleSync(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize, maxPixelSize > 0 else { return image }
        let factor = CGFloat(maxPixelSize) / CGFloat(longest)
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))

        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
