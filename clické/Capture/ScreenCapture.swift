import AppKit
import ImageIO

// MARK: - Screen Capture

/// A successful capture, kept in memory for the preview and "Edit Last Screenshot".
///
/// Only the PNG and a small thumbnail are kept: decoded, a 5K capture weighs ~60 MB, so the full
/// bitmap is decoded again on demand (`makeImage()`) when the editor needs it.
struct ScreenCapture: Identifiable {
    let id = UUID()
    let date: Date
    /// The PNG written by `screencapture`. Reused as-is for the clipboard and saved files:
    /// no re-encoding, and its DPI metadata keeps the right size when pasted elsewhere.
    let pngData: Data
    /// The capture's size in points (a Retina capture has 2 pixels per point).
    let pointSize: CGSize
    /// A small pre-decoded version for the floating preview.
    let thumbnail: CGImage

    init(decoded: DecodedCapture, date: Date = Date()) {
        self.date = date
        self.pngData = decoded.pngData
        self.pointSize = decoded.pointSize
        self.thumbnail = decoded.thumbnail
    }

    /// The capture at full resolution, for the editor. `NSImage` decodes the PNG lazily (when the
    /// editor builds its layer) and takes its point size from the PNG's DPI.
    func makeImage() -> NSImage? {
        guard let image = NSImage(data: pngData), !image.representations.isEmpty else { return nil }
        if pointSize.width > 0, pointSize.height > 0 {
            image.size = pointSize
        }
        return image
    }

    /// The default file name, macOS style: "Clické 2026-10-14 at 11.32.05.png".
    var fileName: String { baseFileName + ".png" }

    /// The default file name without extension.
    var baseFileName: String { Self.baseFileName(for: date) }

    /// The app-wide default file name (without extension) for an image made at `date`:
    /// "Clické 2026-10-14 at 11.32.05". Used for captures and editor exports alike.
    static func baseFileName(for date: Date) -> String {
        let day = dayFormatter.string(from: date)
        let time = timeFormatter.string(from: date)
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
/// The full bitmap (`image`) is only meant to live for the duration of the capture's follow-up
/// (opening the editor right away); `ScreenCapture` keeps the PNG and the thumbnail only.
///
/// `@unchecked Sendable`: `CGImage` and `Data` are immutable and thread-safe.
struct DecodedCapture: @unchecked Sendable {
    let pngData: Data
    let image: CGImage
    /// Size in points, derived from the file's DPI (144 DPI on Retina = 2 pixels per point).
    let pointSize: CGSize
    let thumbnail: CGImage

    /// The decoded bitmap as an `NSImage` of the capture's point size (no new decoding).
    func makeImage() -> NSImage {
        let representation = NSBitmapImageRep(cgImage: image)
        representation.size = pointSize
        let nsImage = NSImage(size: pointSize)
        nsImage.addRepresentation(representation)
        return nsImage
    }
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

        // Scale the bitmap that was just decoded: asking ImageIO for a thumbnail would decode the PNG again.
        let thumbnail = downscaled(image, maxPixelSize: thumbnailMaxPixelSize)

        return DecodedCapture(pngData: data, image: image, pointSize: pointSize, thumbnail: thumbnail)
    }

    /// A copy of `image` whose longest side is at most `maxPixelSize` pixels (`image` itself if smaller).
    private nonisolated static func downscaled(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize else { return image }

        let scale = Double(maxPixelSize) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        // Keep the capture's color space (e.g. Display P3) when an 8-bit context supports it.
        let colorSpaces = [image.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
        for colorSpace in colorSpaces where colorSpace.model == .rgb {
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { continue }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            if let thumbnail = context.makeImage() {
                return thumbnail
            }
        }
        return image
    }
}
