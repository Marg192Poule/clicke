import SwiftUI

// MARK: - Noise Effect Extension
extension View {
    /// Apply noise as overlay layer (for use on blurred backgrounds)
    /// - Parameter intensity: Noise intensity from 0 to 1
    func noiseOverlay(intensity: Double) -> some View {
        self.modifier(NoiseOverlayModifier(intensity: intensity))
    }
    
    /// Apply saturation and brightness adjustments using Metal shader (GPU-accelerated)
    /// - Parameters:
    ///   - saturation: Saturation multiplier (1.0 = normal, 0.0 = grayscale, 2.0 = double)
    ///   - brightness: Brightness offset (-1.0 to 1.0, 0.0 = normal)
    func colorAdjustments(saturation: Double, brightness: Double) -> some View {
        self.modifier(ColorAdjustmentsModifier(saturation: saturation, brightness: brightness))
    }
}

struct NoiseOverlayModifier: ViewModifier {
    let intensity: Double
    
    func body(content: Content) -> some View {
        if intensity > 0 {
            content
                .colorEffect(
                    ShaderLibrary.noiseOverlay(
                        .float(intensity)
                    )
                )
        } else {
            content
        }
    }
}

// MARK: - Color Adjustments (GPU-accelerated saturation & brightness)
struct ColorAdjustmentsModifier: ViewModifier {
    let saturation: Double
    let brightness: Double
    
    func body(content: Content) -> some View {
        // Only apply shader if values differ from default
        if saturation != 1.0 || brightness != 0.0 {
            content
                .colorEffect(
                    ShaderLibrary.adjustColors(
                        .float(saturation),
                        .float(brightness)
                    )
                )
        } else {
            content
        }
    }
}

// MARK: - GPU-accelerated Checkerboard
struct CheckerboardShaderView: View {
    var squareSize: CGFloat = 12
    
    var body: some View {
        Rectangle()
            .colorEffect(
                ShaderLibrary.checkerboard(
                    .float(squareSize)
                )
            )
    }
}

// MARK: - GPU-accelerated Pixelate
struct PixelateShaderView: View {
    var pixelSize: CGFloat = 8
    
    var body: some View {
        Rectangle()
            .colorEffect(
                ShaderLibrary.pixelate(
                    .float(pixelSize)
                )
            )
    }
}

// MARK: - Noise Texture View (standalone overlay layer)
/// A standalone noise texture that can be overlaid on any background
/// This is independent of the background content, so blur won't affect it
struct NoiseTextureView: View {
    var intensity: Double // 0 to 1
    var size: CGSize
    
    var body: some View {
        Rectangle()
            .fill(Color.gray) // Base color for the noise shader to work on
            .frame(width: size.width, height: size.height)
            .colorEffect(
                ShaderLibrary.noiseTexture(
                    .float(intensity)
                )
            )
            .blendMode(.softLight) // softLight preserves luminosity better than overlay
            .allowsHitTesting(false)
    }
}
