import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Encodes rendered images with ImageIO (no `NSImage`/TIFF round trip).
///
/// Files carry a DPI of `72 × pixelDensity`, so a 2× export opens at its point size in
/// Preview, Keynote, Figma… exactly like a macOS screenshot does.
nonisolated enum ImageEncoder {
    enum EncodingError: LocalizedError {
        case cannotEncode(String)

        var errorDescription: String? {
            switch self {
            case .cannotEncode(let format): "The image couldn’t be encoded as \(format)."
            }
        }
    }

    /// Encodes `image` in the given export format.
    static func data(for image: CGImage, format: ExportFormat, jpegQuality: Double = 0.9, pixelDensity: CGFloat = 1) throws -> Data {
        switch format {
        case .png:
            var properties = dpiProperties(pixelDensity)
            // The "sub" filter alone encodes about twice as fast as the adaptive default,
            // for files only a few percent larger.
            properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGCompressionFilter: IMAGEIO_PNG_FILTER_SUB]
            return try encode(image, type: .png, properties: properties, formatName: "PNG")
        case .jpeg:
            var properties = dpiProperties(pixelDensity)
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(jpegQuality, 0), 1)
            return try encode(flattened(image), type: .jpeg, properties: properties, formatName: "JPEG")
        }
    }

    // MARK: Private

    private static func dpiProperties(_ pixelDensity: CGFloat) -> [CFString: Any] {
        let dpi = 72 * max(pixelDensity, 1)
        return [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
    }

    private static func encode(_ image: CGImage, type: UTType, properties: [CFString: Any], formatName: String) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw EncodingError.cannotEncode(formatName)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EncodingError.cannotEncode(formatName) }
        return data as Data
    }

    /// JPEG has no alpha channel: composite transparent pixels over white instead of letting them turn black.
    private static func flattened(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        default:
            break
        }
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }
}
