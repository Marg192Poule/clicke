import AppKit

extension NSImage {
    /// The image at its full native resolution.
    ///
    /// For bitmaps this is the largest representation as-is (a Retina screenshot gives its
    /// 2× pixels, regardless of the screen the app runs on). Vector images are rasterized at 2×.
    var bestCGImage: CGImage? {
        let bitmaps = representations.compactMap { $0 as? NSBitmapImageRep }
        if let largest = bitmaps.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
           let cgImage = largest.cgImage {
            return cgImage
        }

        guard size.width > 0, size.height > 0 else { return nil }
        let largestRep = representations.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh })
        var pixelWidth = CGFloat(largestRep?.pixelsWide ?? 0)
        var pixelHeight = CGFloat(largestRep?.pixelsHigh ?? 0)
        if pixelWidth <= 0 || pixelHeight <= 0 { // vector (PDF, symbols…): rasterize at 2×
            pixelWidth = size.width * 2
            pixelHeight = size.height * 2
        }

        guard let context = CGContext(
            data: nil,
            width: Int(pixelWidth.rounded()),
            height: Int(pixelHeight.rounded()),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw(in: NSRect(x: 0, y: 0, width: pixelWidth.rounded(), height: pixelHeight.rounded()))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
