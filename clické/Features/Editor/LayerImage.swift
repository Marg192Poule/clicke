import AppKit
import Observation
import os

/// The bitmap of a canvas layer: the full-resolution image used for exports, plus a
/// downsampled copy for the live canvas (so a 5K capture isn't sampled 60 times per second).
@Observable
final class LayerImage: Equatable {
    /// Longest side of the preview copy, in pixels.
    nonisolated static let previewMaxPixelSize = 2048

    /// Full resolution bitmap (bounded by `ImageImport`).
    let cgImage: CGImage
    /// Size in points (pixels / pixel density), which defines the layer's natural size.
    let pointSize: CGSize

    /// The preview is written from a background thread as soon as it's ready, so the editor's
    /// first frame (laid out while the window is being built) usually already gets it.
    @ObservationIgnored private let previewStorage = OSAllocatedUnfairLock<CGImage?>(initialState: nil)
    /// Bumped on the main actor when the preview lands, to redraw views that rendered without it.
    private var previewGeneration = 0

    init(_ image: ImportedImage) {
        let cgImage = image.cgImage
        self.cgImage = cgImage
        self.pointSize = image.pointSize

        if max(cgImage.width, cgImage.height) > Self.previewMaxPixelSize {
            let storage = previewStorage
            Task.detached(priority: .userInitiated) { [weak self] in
                let preview = ImageLoadingService.downsampleSync(cgImage, maxPixelSize: Self.previewMaxPixelSize)
                storage.withLock { $0 = preview }
                await self?.previewDidLoad()
            }
        }
    }

    private func previewDidLoad() {
        previewGeneration += 1
    }

    /// Downsampled bitmap for the canvas, once available (`nil` for small images, or while it's computed).
    var preview: CGImage? {
        _ = previewGeneration
        return previewStorage.withLock { $0 }
    }

    /// Native pixels per point (2 for a Retina capture).
    var pixelDensity: CGFloat { CGFloat(cgImage.width) / pointSize.width }

    /// Memory held by the bitmaps, in bytes (bounds the undo history).
    var byteCount: Int {
        let preview = previewStorage.withLock { $0 }
        return cgImage.bytesPerRow * cgImage.height + (preview.map { $0.bytesPerRow * $0.height } ?? 0)
    }

    /// The cheapest bitmap that still looks sharp when drawn `pixelWidth` pixels wide.
    func bitmap(forDisplayPixelWidth pixelWidth: CGFloat) -> CGImage {
        if let preview, pixelWidth <= CGFloat(preview.width) * 1.15 {
            return preview
        }
        return cgImage
    }

    /// The bitmap as an `NSImage` of the layer's point size (the redaction sheet's input).
    func makeNSImage() -> NSImage {
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(representation)
        return image
    }

    static func == (lhs: LayerImage, rhs: LayerImage) -> Bool { lhs === rhs }
}
