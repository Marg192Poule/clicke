#include <SwiftUI/SwiftUI_Metal.h>
#include <metal_stdlib>
using namespace metal;

[[ stitchable ]]
half4 noise(float2 position, half4 color, float intensity) {
    // Scale down position to create uniform grain density
    float2 scaledPos = position * 0.5;
    
    // Generate high-quality random noise
    float value = fract(sin(dot(scaledPos, float2(12.9898, 78.233))) * 43758.5453);
    
    // Create grain: value ranges from -1 to +1, scaled by intensity
    // Increased multiplier from 0.15 to 0.35 for more visible grain
    half grain = half(value * 2.0 - 1.0) * half(intensity) * 0.35;
    
    // Add grain to original color (overlay effect)
    half3 result = clamp(color.rgb + grain, 0.0h, 1.0h);
    
    return half4(result, color.a);
}

[[ stitchable ]]
half4 noiseOverlay(float2 position, half4 color, float intensity) {
    // Use original position for fine grain (no scaling = smaller grain)
    float2 p = position;
    
    // Generate noise value
    float value = fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
    
    // Create stronger grain offset (-0.5 to +0.5 range, centered)
    // Increased multiplier from 0.25 to 0.6 for more visible grain
    half grain = half(value - 0.5) * half(intensity) * 0.6h;
    
    // Mix with original color - adds/subtracts amount
    half3 result = color.rgb + grain;
    
    return half4(clamp(result, 0.0h, 1.0h), color.a);
}

[[ stitchable ]]
half4 grainNoise(float2 position, half4 color, float intensity, float time) {
    // Scale down position for uniform grain density
    float2 scaledPos = position * 0.5;
    
    // Animated grain noise for more natural film grain effect
    float2 seed = scaledPos + float2(time * 0.1);
    float value = fract(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453);
    
    // Create grain pattern with reduced intensity
    half grain = half(value * 2.0 - 1.0) * half(intensity) * 0.12;
    half3 result = clamp(color.rgb + grain, 0.0h, 1.0h);
    
    return half4(result, color.a);
}

// MARK: - Saturation & Brightness Shader (GPU-accelerated)
[[ stitchable ]]
half4 adjustColors(float2 position, half4 color, float saturation, float brightness) {
    // Convert to grayscale for saturation calculation
    half gray = dot(color.rgb, half3(0.299h, 0.587h, 0.114h));
    
    // Apply saturation (1.0 = normal, 0.0 = grayscale, 2.0 = double saturation)
    half3 saturated = mix(half3(gray), color.rgb, half(saturation));
    
    // Apply brightness (-1.0 to 1.0 range, 0.0 = normal)
    half3 result = saturated + half(brightness);
    
    return half4(clamp(result, 0.0h, 1.0h), color.a);
}

// MARK: - Pixelate Shader (static pattern, no flickering)
[[ stitchable ]]
half4 pixelate(float2 position, half4 color, float pixelSize) {
    // Create pixelated coordinates
    float2 pixelPos = floor(position / pixelSize) * pixelSize;
    
    // Generate deterministic random value based on pixel position
    float value = fract(sin(dot(pixelPos, float2(12.9898, 78.233))) * 43758.5453);
    
    // Create gray value
    half grayValue = half(0.2 + value * 0.2); // Range 0.2-0.4
    
    return half4(grayValue, grayValue, grayValue, 1.0h);
}

// MARK: - Noise Texture Shader (standalone grain overlay)
// This creates a pure noise texture for softLight blend mode
// SoftLight with 0.5 gray = no change, <0.5 = darken, >0.5 = lighten
[[ stitchable ]]
half4 noiseTexture(float2 position, half4 color, float intensity) {
    // Generate fine grain noise (0 to 1)
    float value = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453);
    
    // Center at 0.5 and scale by intensity
    // At intensity=0: grain=0.5 (no effect with softLight)
    // At intensity=1: grain ranges from ~0.15 to ~0.85 (increased from 0.3-0.7)
    // Increased multiplier from 0.4 to 0.7 for more visible grain
    half grain = half(0.5 + (value - 0.5) * intensity * 0.7);
    
    // Full opacity - the grain value itself controls the effect
    return half4(grain, grain, grain, 1.0h);
}

// MARK: - Checkerboard Shader (GPU-accelerated)
[[ stitchable ]]
half4 checkerboard(float2 position, half4 color, float squareSize) {
    // Calculate which square we're in
    int col = int(position.x / squareSize);
    int row = int(position.y / squareSize);
    
    // Alternate colors
    bool isLight = ((col + row) % 2) == 0;
    
    half value = isLight ? 0.227h : 0.165h; // #3a3a3a and #2a2a2a
    
    return half4(value, value, value, 1.0h);
}
