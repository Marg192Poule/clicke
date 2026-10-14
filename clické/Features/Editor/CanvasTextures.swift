import SwiftUI

/// Small procedural textures, generated once and tiled.
///
/// The grain is a deterministic image (seeded generator), so the live canvas and the export
/// draw exactly the same pattern, with the same blend mode, through the same SwiftUI views.
nonisolated enum CanvasTextures {
    /// Side of the square grain tile, in pixels.
    static let grainTileSize = 256

    /// Grayscale noise centered on 50% gray (soft light with 50% gray is a no-op).
    static let grain: CGImage = makeGrain(size: grainTileSize, seed: 0x5EED_C11C)

    /// Checkerboard tiles shown behind transparent backgrounds (never exported).
    static let lightCheckerboard: CGImage = makeCheckerboard(light: 1.0, dark: 0.89)
    static let darkCheckerboard: CGImage = makeCheckerboard(light: 0.24, dark: 0.18)

    /// Size of one checkerboard square, in points.
    static let checkerSquare: CGFloat = 8
    private static let checkerScale: CGFloat = 2

    // MARK: Generation

    private static func makeGrain(size: Int, seed: UInt64) -> CGImage {
        var state = seed
        /// SplitMix64: tiny, fast, and identical on every run.
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        var pixels = [UInt8](repeating: 128, count: size * size)
        for index in pixels.indices {
            // Average of two uniform samples: a soft, film-like triangular distribution around 50%.
            let a = Double(next() >> 11) / Double(1 << 53)
            let b = Double(next() >> 11) / Double(1 << 53)
            pixels[index] = UInt8(((a + b) / 2 * 255).rounded())
        }
        return makeGrayImage(pixels: pixels, width: size, height: size)
    }

    private static func makeCheckerboard(light: Double, dark: Double) -> CGImage {
        let cell = Int(checkerSquare * checkerScale)
        let size = cell * 2
        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let isLight = (x / cell + y / cell).isMultiple(of: 2)
                pixels[y * size + x] = UInt8(((isLight ? light : dark) * 255).rounded())
            }
        }
        return makeGrayImage(pixels: pixels, width: size, height: size)
    }

    private static func makeGrayImage(pixels: [UInt8], width: Int, height: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    // MARK: Views

    /// The checkerboard tile as a tiling image, adapted to light or dark mode.
    @MainActor
    static func checkerboard(for colorScheme: ColorScheme) -> some View {
        Image(decorative: colorScheme == .dark ? darkCheckerboard : lightCheckerboard, scale: checkerScale)
            .resizable(resizingMode: .tile)
    }
}

/// Film grain over the background, soft-light blended.
///
/// One grain cell is one canvas point; `scale` maps canvas points to the points of the view
/// being drawn, so the grain keeps the same density on the live canvas and in the export.
struct GrainOverlay: View {
    /// Grain amount, 0–100.
    let amount: Double
    let scale: CGFloat

    var body: some View {
        Image(decorative: CanvasTextures.grain, scale: 1 / max(scale, 0.01))
            .resizable(resizingMode: .tile)
            .interpolation(.low)
            .blendMode(.softLight)
            .opacity(min(max(amount, 0), 100) / 100 * 0.75)
            .allowsHitTesting(false)
    }
}
