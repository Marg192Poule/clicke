import AppKit
import Observation
import os

/// The bitmap of a canvas layer: the full-resolution image used for exports, plus a
/// downsampled copy for the live canvas (so a 5K capture isn't sampled 60 times per second).
@Observable
final class LayerImage: Equatable {
    /// Longest side of the preview copy, in pixels.
    nonisolated static let previewMaxPixelSize = 2048

    /// The image as handed to the editor (used as the redaction input).
    let nsImage: NSImage
    /// Full resolution bitmap.
    let cgImage: CGImage
    /// Size in points (pixels / pixel density), which defines the layer's natural size.
    let pointSize: CGSize

    /// The preview is written from a background thread as soon as it's ready, so the editor's
    /// first frame (laid out while the window is being built) usually already gets it.
    @ObservationIgnored private let previewStorage = OSAllocatedUnfairLock<CGImage?>(initialState: nil)
    /// Bumped on the main actor when the preview lands, to redraw views that rendered without it.
    private var previewGeneration = 0

    init?(nsImage: NSImage) {
        guard let cgImage = nsImage.bestCGImage, cgImage.width > 0, cgImage.height > 0 else { return nil }
        self.nsImage = nsImage
        self.cgImage = cgImage
        let size = nsImage.size
        self.pointSize = size.width > 0 && size.height > 0
            ? size
            : CGSize(width: cgImage.width, height: cgImage.height)

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

    /// The cheapest bitmap that still looks sharp when drawn `pixelWidth` pixels wide.
    func bitmap(forDisplayPixelWidth pixelWidth: CGFloat) -> CGImage {
        if let preview, pixelWidth <= CGFloat(preview.width) * 1.15 {
            return preview
        }
        return cgImage
    }

    static func == (lhs: LayerImage, rhs: LayerImage) -> Bool { lhs === rhs }
}
