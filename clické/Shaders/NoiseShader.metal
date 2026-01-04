#include <SwiftUI/SwiftUI_Metal.h>
#include <metal_stdlib>
using namespace metal;

[[ stitchable ]]
half4 noise(float2 position, half4 color, float intensity) {
    // Generate high-quality random noise
    float value = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453);
    
    // Create grain: value ranges from -1 to +1, scaled by intensity
    half grain = half(value * 2.0 - 1.0) * half(intensity) * 0.15;
    
    // Add grain to original color (overlay effect)
    half3 result = clamp(color.rgb + grain, 0.0h, 1.0h);
    
    return half4(result, color.a);
}

[[ stitchable ]]
half4 noiseOverlay(float2 position, half4 color, float intensity) {
    // Generate high-quality random noise for overlay
    float value = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453);
    
    // Create pure black/white grain (-1 to +1 range)
    half grain = half(value * 2.0 - 1.0) * half(intensity);
    
    // Return semi-transparent grain with higher intensity (0.35 instead of 0.15)
    // This creates a more visible neutral grain overlay
    half grayValue = 0.5h + grain * 0.35h;
    
    return half4(grayValue, grayValue, grayValue, 1.0h);
}

[[ stitchable ]]
half4 grainNoise(float2 position, half4 color, float intensity, float time) {
    // Animated grain noise for more natural film grain effect
    float2 seed = position + float2(time * 0.1);
    float value = fract(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453);
    
    // Create grain pattern with reduced intensity
    half grain = half(value * 2.0 - 1.0) * half(intensity) * 0.12;
    half3 result = clamp(color.rgb + grain, 0.0h, 1.0h);
    
    return half4(result, color.a);
}
