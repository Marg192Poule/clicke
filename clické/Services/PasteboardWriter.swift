import AppKit
import ImageIO
import UniformTypeIdentifiers
import os

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clicke", category: "Pasteboard")

// MARK: - Pasteboard Writer

/// Puts images on the general pasteboard the same way everywhere in the app (captures and editor).
///
/// PNG is written right away (compact, keeps transparency and the Retina DPI). TIFF, which a few
/// older apps still require, is only *promised*: it's encoded from the PNG if and when an app
/// actually asks for it. A 5K capture as uncompressed TIFF is ~56 MB, so producing it eagerly on
/// every copy would waste time and memory and bloat clipboard managers.
enum PasteboardWriter {
    /// Replaces the clipboard contents with `pngData`.
    /// - Returns: `false` if the pasteboard refused the data.
    @discardableResult
    static func writePNG(_ pngData: Data) -> Bool {
        let provider = LazyTIFFProvider(pngData: pngData)
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        item.setDataProvider(provider, forTypes: [.tiff])

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            logger.error("Couldn't write the image to the pasteboard")
            return false
        }
        LazyTIFFProvider.retain(provider)
        return true
    }
}

// MARK: - Lazy TIFF Provider

/// Encodes TIFF from the PNG on demand. Holds only the (immutable) PNG bytes.
private nonisolated final class LazyTIFFProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let pngData: Data

    /// Providers must stay alive until the pasteboard is done with them.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storage: [ObjectIdentifier: LazyTIFFProvider] = [:]

    init(pngData: Data) {
        self.pngData = pngData
    }

    static func retain(_ provider: LazyTIFFProvider) {
        lock.lock(); defer { lock.unlock() }
        storage[ObjectIdentifier(provider)] = provider
    }

    private static func release(_ provider: LazyTIFFProvider) {
        lock.lock(); defer { lock.unlock() }
        storage[ObjectIdentifier(provider)] = nil
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let tiff = Self.tiffData(fromPNG: pngData) else { return }
        item.setData(tiff, forType: .tiff)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        Self.release(self)
    }

    /// Re-encodes PNG bytes as LZW-compressed TIFF, keeping alpha and DPI.
    private static func tiffData(fromPNG pngData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5] // LZW
        ]
        if let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            properties[kCGImagePropertyDPIWidth] = original[kCGImagePropertyDPIWidth]
            properties[kCGImagePropertyDPIHeight] = original[kCGImagePropertyDPIHeight]
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
