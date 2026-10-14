import AppKit
import ImageIO

// MARK: - Screen Capture

/// A successful capture, kept in memory for the preview, the editor and "Edit Last Capture".
struct ScreenCapture: Identifiable {
    let id = UUID()
    let date: Date
    /// The capture at its real point size (a Retina capture has 2 pixels per point).
    let image: NSImage
    /// The full-resolution bitmap behind `image`.
    let cgImage: CGImage
    /// The PNG written by `screencapture`. Reused as-is for the clipboard and saved files:
    /// no re-encoding, and its DPI metadata keeps the right size when pasted elsewhere.
    let pngData: Data
    /// A small pre-decoded version for the floating preview.
    let thumbnail: CGImage

    init(decoded: DecodedCapture, date: Date = Date()) {
        let representation = NSBitmapImageRep(cgImage: decoded.image)
        representation.size = decoded.pointSize
        let image = NSImage(size: decoded.pointSize)
        image.addRepresentation(representation)

        self.date = date
        self.image = image
        self.cgImage = decoded.image
        self.pngData = decoded.pngData
        self.thumbnail = decoded.thumbnail
    }

    /// The default file name, macOS style: "Clické 2026-10-14 at 11.32.05.png".
    var fileName: String { baseFileName + ".png" }

    /// The default file name without extension.
    var baseFileName: String {
        let day = Self.dayFormatter.string(from: date)
        let time = Self.timeFormatter.string(from: date)
        return String(localized: "Clické \(day) at \(time)", comment: "Default file name of a capture: date, then time")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH.mm.ss"
        return formatter
    }()
}

// MARK: - Decoding

/// A capture file decoded off the main thread.
///
/// `@unchecked Sendable`: `CGImage` and `Data` are immutable and thread-safe.
struct DecodedCapture: @unchecked Sendable {
    let pngData: Data
    let image: CGImage
    /// Size in points, derived from the file's DPI (144 DPI on Retina = 2 pixels per point).
    let pointSize: CGSize
    let thumbnail: CGImage
}

/// ImageIO helpers that run off the main thread.
enum CaptureImageIO {
    /// Longest side, in pixels, of the preview thumbnail (enough for a 240 pt card on Retina).
    private nonisolated static let thumbnailMaxPixelSize = 640

    /// Reads and decodes a PNG written by `screencapture`, preserving its DPI.
    /// The file can be deleted as soon as this returns: everything is loaded in memory.
    @concurrent
    nonisolated static func decodeCapture(at url: URL) async -> DecodedCapture? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpiX = (properties?[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        let dpiY = (properties?[kCGImagePropertyDPIHeight] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        let pointSize = CGSize(
            width: Double(image.width) * 72 / dpiX,
            height: Double(image.height) * 72 / dpiY
        )

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
        ]
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) ?? image

        return DecodedCapture(pngData: data, image: image, pointSize: pointSize, thumbnail: thumbnail)
    }

    /// Encodes `image` as TIFF (keeps transparency) with DPI metadata matching `pointSize`.
    @concurrent
    nonisolated static func tiffData(for image: SendableImage, pointSize: CGSize) async -> Data? {
        let data = NSMutableData()
        guard pointSize.width > 0, pointSize.height > 0,
              let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.tiff" as CFString, 1, nil)
        else { return nil }

        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: Double(image.cgImage.width) * 72 / pointSize.width,
            kCGImagePropertyDPIHeight: Double(image.cgImage.height) * 72 / pointSize.height
        ]
        CGImageDestinationAddImage(destination, image.cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// Wraps a `CGImage` to hand it to a background task (`CGImage` is immutable and thread-safe).
struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage
}
