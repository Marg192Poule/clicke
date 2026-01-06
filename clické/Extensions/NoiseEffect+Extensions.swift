import SwiftUI

// MARK: - Noise Effect Extension
extension View {
    /// Apply noise overlay effect using Metal shader
    /// - Parameter intensity: Noise intensity from 0 to 1
    func noiseEffect(intensity: Double) -> some View {
        self.modifier(NoiseEffectModifier(intensity: intensity))
    }
    
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

struct NoiseEffectModifier: ViewModifier {
    let intensity: Double
    
    func body(content: Content) -> some View {
        if intensity > 0 {
            content
                .colorEffect(
                    ShaderLibrary.noise(
                        .float(intensity)
                    )
                )
        } else {
            content
        }
    }
}

struct NoiseOverlayModifier: ViewModifier {
    let intensity: Double
    
    func body(content: Content) -> some View {
        if intensity > 0 {
            content
                .overlay {
                    Rectangle()
                        .colorEffect(
                            ShaderLibrary.noiseOverlay(
                                .float(intensity)
                            )
                        )
                        .blendMode(.softLight)
                        .opacity(min(intensity * 1.2, 1.0))
                        .allowsHitTesting(false)
                }
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
