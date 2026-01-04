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
                        .blendMode(.softLight) // Neutral blend mode that doesn't alter colors
                        .opacity(min(intensity * 1.2, 1.0)) // Higher opacity for more visible grain
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}
