import SwiftUI
import AppKit
import os

// MARK: - ScreenshotRenderer

/// Renders the canvas into a bitmap for Copy, Save and drag-out.
///
/// The export draws the very same SwiftUI views as the live canvas (`ExportCanvasView`), laid out
/// in pixels and rendered into a `CGContext` of the exact export size, so it's deterministic:
/// it doesn't depend on the screen the app runs on, and the canvas is what you get.
enum ScreenshotRenderer {
    /// A rendered export.
    struct Output: @unchecked Sendable {
        let image: CGImage
        /// Export pixels per point (written to the file's DPI).
        let pixelDensity: CGFloat
    }

    nonisolated enum RenderError: LocalizedError {
        case failed

        var errorDescription: String? { String(localized: "The image couldn’t be rendered.") }
    }

    // MARK: Rendering

    /// Full-resolution export. Decodes the background off the main actor, then renders.
    static func render(config: ScreenshotStyleConfig, items: [CanvasItem]) async -> Output? {
        let geometry = CanvasGeometry(config: config, items: items)
        let background = await backgroundImage(for: config, pixelSize: geometry.pixelSize)
        return render(config: config, items: items, geometry: geometry, background: background)
    }

    /// Full-resolution export with an already decoded background.
    static func render(config: ScreenshotStyleConfig, items: [CanvasItem], geometry: CanvasGeometry, background: CGImage?) -> Output? {
        let view = ExportCanvasView(
            config: config,
            items: items,
            geometry: geometry,
            background: background,
            scale: geometry.pixelScale
        )
        guard let image = rasterize(view, pixelSize: geometry.pixelSize, isOpaque: config.isOpaque) else {
            Logger.editor.error("Rendering the export failed (\(Int(geometry.pixelSize.width))×\(Int(geometry.pixelSize.height)) px).")
            return nil
        }
        return Output(image: image, pixelDensity: geometry.pixelScale)
    }

    /// A small rendering of the canvas (previews and drag images), from the preview bitmaps.
    static func renderThumbnail(config: ScreenshotStyleConfig, items: [CanvasItem], background: CGImage?, maxPixelSize: CGFloat) -> CGImage? {
        let geometry = CanvasGeometry(config: config, items: items)
        let longest = max(geometry.canvasSize.width, geometry.canvasSize.height)
        guard longest > 0 else { return nil }
        let scale = maxPixelSize / longest
        let view = ExportCanvasView(
            config: config,
            items: items,
            geometry: geometry,
            background: background,
            scale: scale,
            usesFullResolution: false
        )
        let pixelSize = CGSize(
            width: max(1, (geometry.canvasSize.width * scale).rounded()),
            height: max(1, (geometry.canvasSize.height * scale).rounded())
        )
        return rasterize(view, pixelSize: pixelSize, isOpaque: config.isOpaque)
    }

    /// The background image decoded at the size the export needs (cached).
    static func backgroundImage(for config: ScreenshotStyleConfig, pixelSize: CGSize) async -> CGImage? {
        guard config.backgroundType == .image, let url = config.backgroundImage.url else { return nil }
        return await ImageLoadingService.cachedImage(at: url, covering: pixelSize)
    }

    /// Renders `view` (laid out in pixels) into an sRGB bitmap of exactly `pixelSize`.
    private static func rasterize(_ view: some View, pixelSize: CGSize, isOpaque: Bool) -> CGImage? {
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: (isOpaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
              ) else { return nil }

        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(pixelSize)
        renderer.scale = 1
        renderer.isOpaque = isOpaque

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if let image = renderer.cgImage, image.width == width, image.height == height {
            // GPU rendering (the same renderer as the canvas, ~10× faster than drawing with Core
            // Graphics). The image renders lazily: drawing it here forces that on the main actor.
            context.draw(image, in: bounds)
        } else {
            // Core Graphics fallback, e.g. for canvases beyond the GPU's texture size limit.
            renderer.render(rasterizationScale: 1) { _, draw in
                draw(context)
            }
        }
        return context.makeImage()
    }

    // MARK: Output

    /// Puts the image on the clipboard as PNG (with transparency) and TIFF, which every app can paste.
    static func copyToPasteboard(_ output: Output) async throws {
        let (png, tiff) = try await encodeForPasteboard(output)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: String(localized: "The image couldn’t be copied to the clipboard.")])
        }
    }

    @concurrent
    private static func encodeForPasteboard(_ output: Output) async throws -> (Data, Data) {
        let png = try ImageEncoder.data(for: output.image, format: .png, pixelDensity: output.pixelDensity)
        let tiff = try ImageEncoder.tiffData(for: output.image, pixelDensity: output.pixelDensity)
        return (png, tiff)
    }

    /// Encodes and writes the image to `url` (off the main actor).
    @concurrent
    static func write(_ output: Output, to url: URL, format: ExportFormat, jpegQuality: Double) async throws {
        let data = try ImageEncoder.data(for: output.image, format: format, jpegQuality: jpegQuality, pixelDensity: output.pixelDensity)
        try data.write(to: url, options: .atomic)
    }
}
