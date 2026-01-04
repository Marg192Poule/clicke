import SwiftUI
import AppKit

// MARK: - Mockup Style (comme shots.so)
enum MockupStyle: String, CaseIterable, Identifiable {
    case defaultStyle
    case glassLight
    case glassDark
    case liquidGlass
    case insetLight
    case insetDark
    case outline
    case border
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .defaultStyle: return "Default"
        case .glassLight: return "Glass Light"
        case .glassDark: return "Glass Dark"
        case .liquidGlass: return "Liquid..."
        case .insetLight: return "Inset Light"
        case .insetDark: return "Inset Dark"
        case .outline: return "Outline"
        case .border: return "Border"
        }
    }
    
    var gradient: LinearGradient {
        switch self {
        case .defaultStyle: return LinearGradient(colors: [.gray.opacity(0.3)], startPoint: .top, endPoint: .bottom)
        case .glassLight: return LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        case .glassDark: return LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        case .liquidGlass: return LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .insetLight: return LinearGradient(colors: [.gray.opacity(0.2), .gray.opacity(0.1)], startPoint: .top, endPoint: .bottom)
        case .insetDark: return LinearGradient(colors: [.black.opacity(0.4), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        case .outline: return LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
        case .border: return LinearGradient(colors: [.gray.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Border Style
enum BorderStyle: String, CaseIterable, Identifiable {
    case sharp
    case curved
    case round
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .sharp: return "Sharp"
        case .curved: return "Curved"
        case .round: return "Round"
        }
    }
    
    var cornerRadius: CGFloat {
        switch self {
        case .sharp: return 0
        case .curved: return 12
        case .round: return 24
        }
    }
}

// MARK: - Background Type
enum BackgroundType: String, CaseIterable, Identifiable {
    case transparent
    case color
    case gradient
    case image
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .transparent: return "Transparent"
        case .color: return "Color"
        case .gradient: return "Gradient"
        case .image: return "Image"
        }
    }
    
    var icon: String {
        switch self {
        case .transparent: return "checkerboard.rectangle"
        case .color: return "circle.fill"
        case .gradient: return "circle.lefthalf.striped.horizontal"
        case .image: return "photo"
        }
    }
}

// MARK: - Magic Color Preset
struct MagicPreset: Identifiable, Equatable {
    let id = UUID()
    let colors: [Color]
    let isPremium: Bool
    
    static let presets: [MagicPreset] = [
        // Row 1 - Neutrals
        MagicPreset(colors: [Color(hex: "ffffff")], isPremium: false),
        MagicPreset(colors: [Color(hex: "2d2d2d")], isPremium: false),
        MagicPreset(colors: [Color(hex: "8b7355"), Color(hex: "d4c4a8")], isPremium: false),
        MagicPreset(colors: [Color(hex: "4a6572"), Color(hex: "8fb3c9")], isPremium: false),
        
        // Row 2 - Light tones
        MagicPreset(colors: [Color(hex: "f5f5f5")], isPremium: false),
        MagicPreset(colors: [Color(hex: "ffd93d"), Color(hex: "ff6b6b")], isPremium: false),
        MagicPreset(colors: [Color(hex: "c9b037"), Color(hex: "6b5b3b")], isPremium: false),
        MagicPreset(colors: [Color(hex: "667eea"), Color(hex: "764ba2")], isPremium: false),
        
        // Row 3 - Warm tones
        MagicPreset(colors: [Color(hex: "f0e6d3")], isPremium: false),
        MagicPreset(colors: [Color(hex: "ff9a56"), Color(hex: "ff6b95")], isPremium: false),
        MagicPreset(colors: [Color(hex: "a8edea"), Color(hex: "fed6e3")], isPremium: false),
        MagicPreset(colors: [Color(hex: "11998e"), Color(hex: "38ef7d")], isPremium: false),
        
        // Row 4 - Dark tones
        MagicPreset(colors: [Color(hex: "1a1a2e")], isPremium: false),
        MagicPreset(colors: [Color(hex: "f953c6"), Color(hex: "b91d73")], isPremium: false),
        MagicPreset(colors: [Color(hex: "4facfe"), Color(hex: "00f2fe")], isPremium: false),
        MagicPreset(colors: [Color(hex: "ee0979"), Color(hex: "ff6a00")], isPremium: false),
    ]
}

// MARK: - Shadow Scene (texture backgrounds)
struct ShadowScene: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let colors: [Color]
    let isTexture: Bool
    
    static let scenes: [ShadowScene] = [
        ShadowScene(name: "Cream", colors: [Color(hex: "f5e6d3"), Color(hex: "e8d4b8")], isTexture: true),
        ShadowScene(name: "Sand", colors: [Color(hex: "d4b896"), Color(hex: "c4a576")], isTexture: true),
        ShadowScene(name: "Paper", colors: [Color(hex: "f8f8f8"), Color(hex: "e8e8e8")], isTexture: true),
        ShadowScene(name: "Light Wood", colors: [Color(hex: "deb887"), Color(hex: "c4a574")], isTexture: true),
        ShadowScene(name: "Birch", colors: [Color(hex: "f5deb3"), Color(hex: "daa520")], isTexture: true),
        ShadowScene(name: "Plant", colors: [Color(hex: "90a955"), Color(hex: "4f772d")], isTexture: true),
        ShadowScene(name: "Concrete", colors: [Color(hex: "95a5a6"), Color(hex: "7f8c8d")], isTexture: true),
        ShadowScene(name: "Pine", colors: [Color(hex: "d2b48c"), Color(hex: "bc9b6a")], isTexture: true),
        ShadowScene(name: "Marble", colors: [Color(hex: "ecf0f1"), Color(hex: "bdc3c7")], isTexture: true),
        ShadowScene(name: "Oak", colors: [Color(hex: "8b4513"), Color(hex: "654321")], isTexture: true),
        ShadowScene(name: "Slate", colors: [Color(hex: "708090"), Color(hex: "4a5568")], isTexture: true),
        ShadowScene(name: "Walnut", colors: [Color(hex: "5d4037"), Color(hex: "3e2723")], isTexture: true),
        ShadowScene(name: "Black Marble", colors: [Color(hex: "2c3e50"), Color(hex: "1a252f")], isTexture: true),
        ShadowScene(name: "Grunge", colors: [Color(hex: "3d3d3d"), Color(hex: "1a1a1a")], isTexture: true),
        ShadowScene(name: "Metal", colors: [Color(hex: "4a4a4a"), Color(hex: "2d2d2d")], isTexture: true),
        ShadowScene(name: "Gold", colors: [Color(hex: "ffd700"), Color(hex: "b8860b")], isTexture: true),
    ]
}

// MARK: - Solid Colors
struct SolidColor: Identifiable, Equatable {
    let id = UUID()
    let color: Color
    
    static let colors: [SolidColor] = [
        SolidColor(color: Color(hex: "f8f9fa")),
        SolidColor(color: Color(hex: "343a40")),
        SolidColor(color: Color(hex: "adb5bd")),
        SolidColor(color: Color(hex: "dee2e6")),
    ]
}

// MARK: - Gradient Presets
struct GradientPreset: Identifiable, Equatable {
    let id = UUID()
    let colors: [Color]
    let angle: Double
    
    static let presets: [GradientPreset] = [
        GradientPreset(colors: [Color(hex: "ff6b6b"), Color(hex: "feca57")], angle: 135),
        GradientPreset(colors: [Color(hex: "667eea"), Color(hex: "764ba2")], angle: 135),
        GradientPreset(colors: [Color(hex: "a8edea"), Color(hex: "fed6e3")], angle: 135),
        GradientPreset(colors: [Color(hex: "11998e"), Color(hex: "38ef7d")], angle: 135),
        GradientPreset(colors: [Color(hex: "fc466b"), Color(hex: "3f5efb")], angle: 135),
        GradientPreset(colors: [Color(hex: "00c6fb"), Color(hex: "005bea")], angle: 135),
        GradientPreset(colors: [Color(hex: "f093fb"), Color(hex: "f5576c")], angle: 135),
        GradientPreset(colors: [Color(hex: "4facfe"), Color(hex: "00f2fe")], angle: 135),
    ]
}

// MARK: - Mesh Gradient Style
enum MeshGradientStyle: String, CaseIterable, Identifiable {
    case mesh
    case linear
    case radial
    case angular
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .mesh: return "Mesh"
        case .linear: return "Linear"
        case .radial: return "Radial"
        case .angular: return "Angular"
        }
    }
    
    var icon: String {
        switch self {
        case .mesh: return "circle.hexagongrid.fill"
        case .linear: return "arrow.up.right"
        case .radial: return "circle.dashed"
        case .angular: return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Mesh Gradient Configuration
struct MeshGradientConfig: Equatable {
    var style: MeshGradientStyle = .mesh
    var color1: Color = Color(hex: "667eea")  // Primary accent
    var color2: Color = Color(hex: "f953c6")  // Secondary accent
    var color3: Color = Color(hex: "0f0c29")  // Deep background
    var color4: Color = Color(hex: "764ba2")  // Mid tone
    
    // Effects
    var blurAmount: Double = 0               // Blur for softer transitions (0-150)
    var noiseAmount: Double = 0              // Grain/noise overlay (0-100)
    var saturation: Double = 100             // Color saturation (0-200)
    var brightness: Double = 100             // Brightness adjustment (50-150)
    
    static let `default` = MeshGradientConfig()
    
    // Create gradient view based on style with effects
    @ViewBuilder
    func gradientView(size: CGSize) -> some View {
        gradientBase(size: size)
            .saturation(saturation / 100)
            .brightness((brightness - 100) / 100)
            .blur(radius: blurAmount) // Blur the gradient
            .noiseOverlay(intensity: noiseAmount / 100) // Noise overlay on top (stays sharp)
            .frame(width: size.width, height: size.height)
    }
    
    @ViewBuilder
    private func gradientBase(size: CGSize) -> some View {
        switch style {
        case .mesh:
            // Organic mesh with offset points for fluid look
            MeshGradient(
                width: 4,
                height: 4,
                points: [
                    // Row 0 - slight wave
                    [0.0, 0.0], [0.35, -0.05], [0.7, 0.05], [1.0, 0.0],
                    // Row 1 - organic curve
                    [-0.05, 0.3], [0.25, 0.35], [0.75, 0.25], [1.05, 0.35],
                    // Row 2 - flowing
                    [0.0, 0.65], [0.4, 0.7], [0.6, 0.6], [1.0, 0.7],
                    // Row 3 - base wave
                    [0.0, 1.0], [0.3, 1.05], [0.7, 0.95], [1.0, 1.0]
                ],
                colors: [
                    // Row 0
                    color3, color1, color2, color3,
                    // Row 1
                    color1, color4, color1, color2,
                    // Row 2
                    color2, color1, color4, color1,
                    // Row 3
                    color3, color2, color1, color3
                ],
                smoothsColors: true
            )
        case .linear:
            LinearGradient(
                stops: [
                    .init(color: color1, location: 0.0),
                    .init(color: color4, location: 0.3),
                    .init(color: color2, location: 0.6),
                    .init(color: color3, location: 1.0)
                ],
                startPoint: UnitPoint(x: 0, y: 0),
                endPoint: UnitPoint(x: 1, y: 1)
            )
        case .radial:
            ZStack {
                // Base layer
                RadialGradient(
                    colors: [color1, color2, color3],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.7
                )
                // Overlay for depth
                RadialGradient(
                    colors: [color4.opacity(0.6), .clear],
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.4
                )
            }
        case .angular:
            ZStack {
                AngularGradient(
                    stops: [
                        .init(color: color1, location: 0.0),
                        .init(color: color4, location: 0.25),
                        .init(color: color2, location: 0.5),
                        .init(color: color3, location: 0.75),
                        .init(color: color1, location: 1.0)
                    ],
                    center: .center
                )
                // Soft center
                RadialGradient(
                    colors: [color3.opacity(0.8), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.3
                )
            }
        }
    }
}

// MARK: - Grain/Noise Overlay (Using Metal Shader for overlay effect)
struct GrainOverlay: View {
    let intensity: Double // 0 to 1
    
    var body: some View {
        Rectangle()
            .fill(.white)
            .colorEffect(
                ShaderLibrary.noise(
                    .float(intensity)
                )
            )
            .allowsHitTesting(false)
            .blendMode(.overlay)
            .opacity(intensity * 0.5) // Reduce overall opacity for subtlety
    }
}

// MARK: - Mesh Gradient Presets
struct MeshGradientPreset: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let config: MeshGradientConfig
    
    static func == (lhs: MeshGradientPreset, rhs: MeshGradientPreset) -> Bool {
        lhs.id == rhs.id
    }
    
    static let presets: [MeshGradientPreset] = [
        // Cosmic Purple - vibrant and modern
        MeshGradientPreset(name: "Cosmic", config: MeshGradientConfig(
            color1: Color(hex: "667eea"),
            color2: Color(hex: "f953c6"),
            color3: Color(hex: "0f0c29"),
            color4: Color(hex: "764ba2")
        )),
        // Ocean Depth
        MeshGradientPreset(name: "Ocean", config: MeshGradientConfig(
            color1: Color(hex: "00d2ff"),
            color2: Color(hex: "3a7bd5"),
            color3: Color(hex: "0a192f"),
            color4: Color(hex: "667eea")
        )),
        // Aurora Borealis
        MeshGradientPreset(name: "Aurora", config: MeshGradientConfig(
            color1: Color(hex: "00f260"),
            color2: Color(hex: "0575e6"),
            color3: Color(hex: "0d1b2a"),
            color4: Color(hex: "38ef7d")
        )),
        // Sunset Vibes
        MeshGradientPreset(name: "Sunset", config: MeshGradientConfig(
            color1: Color(hex: "ff6b6b"),
            color2: Color(hex: "feca57"),
            color3: Color(hex: "1a1a2e"),
            color4: Color(hex: "ff9ff3")
        )),
        // Neon Nights
        MeshGradientPreset(name: "Neon", config: MeshGradientConfig(
            color1: Color(hex: "f953c6"),
            color2: Color(hex: "00ffff"),
            color3: Color(hex: "0a0a0a"),
            color4: Color(hex: "b91d73")
        )),
        // Cotton Candy
        MeshGradientPreset(name: "Candy", config: MeshGradientConfig(
            color1: Color(hex: "ffecd2"),
            color2: Color(hex: "fcb69f"),
            color3: Color(hex: "f8b4d9"),
            color4: Color(hex: "a8edea")
        )),
        // Deep Space
        MeshGradientPreset(name: "Space", config: MeshGradientConfig(
            color1: Color(hex: "4158d0"),
            color2: Color(hex: "c850c0"),
            color3: Color(hex: "000000"),
            color4: Color(hex: "ffcc70")
        )),
        // Emerald Dream
        MeshGradientPreset(name: "Emerald", config: MeshGradientConfig(
            color1: Color(hex: "11998e"),
            color2: Color(hex: "38ef7d"),
            color3: Color(hex: "0b3d0b"),
            color4: Color(hex: "56ab2f")
        )),
        // Fire & Ice
        MeshGradientPreset(name: "Contrast", config: MeshGradientConfig(
            color1: Color(hex: "ff416c"),
            color2: Color(hex: "74ebd5"),
            color3: Color(hex: "0f0f0f"),
            color4: Color(hex: "ff4b2b")
        )),
        // Lavender Mist
        MeshGradientPreset(name: "Lavender", config: MeshGradientConfig(
            color1: Color(hex: "e0c3fc"),
            color2: Color(hex: "8ec5fc"),
            color3: Color(hex: "2d1b69"),
            color4: Color(hex: "c471ed")
        )),
        // Midnight Blue
        MeshGradientPreset(name: "Midnight", config: MeshGradientConfig(
            color1: Color(hex: "2c3e50"),
            color2: Color(hex: "4ca1af"),
            color3: Color(hex: "000428"),
            color4: Color(hex: "004e92")
        )),
        // Warm Glow
        MeshGradientPreset(name: "Warm", config: MeshGradientConfig(
            color1: Color(hex: "f7971e"),
            color2: Color(hex: "ffd200"),
            color3: Color(hex: "2d1f0f"),
            color4: Color(hex: "ff5f6d")
        )),
    ]
}

// MARK: - Shadow Scene Mode
enum ShadowSceneMode: String, CaseIterable, Identifiable {
    case underlay
    case overlay
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .underlay: return "Underlay"
        case .overlay: return "Overlay"
        }
    }
}

// MARK: - Text Overlay
struct TextOverlay: Identifiable, Equatable {
    let id = UUID()
    var text: String = "Text"
    var fontSize: CGFloat = 24
    var fontWeight: Font.Weight = .semibold
    var color: Color = .white
    var position: CGPoint = .zero
    var rotation: Double = 0
    var opacity: Double = 1.0
    var isBlurred: Bool = false // Pour masquer/crypter le texte
}

// MARK: - Redact Region
struct RedactRegion: Identifiable, Equatable {
    let id = UUID()
    var rect: CGRect
    var style: RedactStyle = .blur
}

enum RedactStyle: String, CaseIterable, Identifiable {
    case blur
    case pixelate
    case blackBar
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .blackBar: return "Black Bar"
        }
    }
    
    var icon: String {
        switch self {
        case .blur: return "aqi.medium"
        case .pixelate: return "square.dashed"
        case .blackBar: return "rectangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .blur: return .purple
        case .pixelate: return .orange
        case .blackBar: return .gray
        }
    }
}

// MARK: - Social Media Export Presets
struct SocialMediaPreset: Identifiable, Equatable {
    let id = UUID()
    let platform: String
    let name: String
    let width: Int
    let height: Int
    let icon: String
    let ratio: String
    
    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(height)
    }
    
    static let presets: [SocialMediaPreset] = [
        // Twitter
        SocialMediaPreset(platform: "Twitter", name: "Tweet", width: 1200, height: 675, icon: "bird", ratio: "16:9"),
        SocialMediaPreset(platform: "Twitter", name: "Cover", width: 1500, height: 500, icon: "bird", ratio: "3:1"),
        
        // YouTube
        SocialMediaPreset(platform: "YouTube", name: "Thumbnail", width: 1280, height: 720, icon: "play.rectangle.fill", ratio: "16:9"),
        SocialMediaPreset(platform: "YouTube", name: "Banner", width: 2560, height: 1440, icon: "play.rectangle.fill", ratio: "16:9"),
        
        // Instagram
        SocialMediaPreset(platform: "Instagram", name: "Post", width: 1080, height: 1080, icon: "camera", ratio: "1:1"),
        SocialMediaPreset(platform: "Instagram", name: "Portrait", width: 1080, height: 1350, icon: "camera", ratio: "4:5"),
        SocialMediaPreset(platform: "Instagram", name: "Story", width: 1080, height: 1920, icon: "camera", ratio: "9:16"),
        
        // Pinterest
        SocialMediaPreset(platform: "Pinterest", name: "Long", width: 1000, height: 2100, icon: "pin", ratio: "10:21"),
        SocialMediaPreset(platform: "Pinterest", name: "Optimal", width: 1000, height: 1500, icon: "pin", ratio: "2:3"),
        SocialMediaPreset(platform: "Pinterest", name: "Square", width: 1000, height: 1000, icon: "pin", ratio: "1:1"),
        
        // Dribbble
        SocialMediaPreset(platform: "Dribbble", name: "Shot", width: 1600, height: 1200, icon: "basketball", ratio: "4:3"),
        SocialMediaPreset(platform: "Dribbble", name: "Full", width: 1600, height: 2400, icon: "basketball", ratio: "2:3"),
        
        // LinkedIn
        SocialMediaPreset(platform: "LinkedIn", name: "Post", width: 1200, height: 627, icon: "person.crop.rectangle", ratio: "1.91:1"),
        SocialMediaPreset(platform: "LinkedIn", name: "Cover", width: 1584, height: 396, icon: "person.crop.rectangle", ratio: "4:1"),
        
        // Common Sizes
        SocialMediaPreset(platform: "Standard", name: "16:9", width: 1920, height: 1080, icon: "rectangle", ratio: "16:9"),
        SocialMediaPreset(platform: "Standard", name: "4:3", width: 1920, height: 1440, icon: "rectangle", ratio: "4:3"),
        SocialMediaPreset(platform: "Standard", name: "1:1", width: 1080, height: 1080, icon: "square", ratio: "1:1"),
        SocialMediaPreset(platform: "Standard", name: "3:2", width: 1920, height: 1280, icon: "rectangle", ratio: "3:2"),
    ]
    
    static var groupedByPlatform: [String: [SocialMediaPreset]] {
        Dictionary(grouping: presets) { $0.platform }
    }
}

// MARK: - Screenshot Style Configuration
struct ScreenshotStyleConfig: Equatable {
    // Mockup
    var mockupStyle: MockupStyle = .defaultStyle
    var showMockup: Bool = true
    var mockupBorderSize: CGFloat = 3 // Taille du contour du style (0-10)
    
    // Border
    var borderStyle: BorderStyle = .curved
    var borderRadius: CGFloat = 20
    
    // Transform
    var rotation: Double = 0
    var imageScale: CGFloat = 100 // Scale of the screenshot itself (100 = 100%)
    var screenshotOffset: CGSize = .zero // Offset to move screenshot within the canvas
    
    // 3D Transform
    var rotationX: Double = 0 // Rotation autour de l'axe X en degrés
    var rotationY: Double = 0 // Rotation autour de l'axe Y en degrés
    var perspective: Double = 0 // Perspective (0-1000, plus élevé = plus de perspective)
    
    // Background
    var backgroundType: BackgroundType = .image
    var selectedMagicPreset: MagicPreset? = MagicPreset.presets[7] // Default purple gradient
    var selectedShadowScene: ShadowScene? = nil
    var selectedSolidColor: SolidColor? = nil
    var selectedGradient: GradientPreset? = nil
    var backgroundImageURL: URL? = nil
    var customColor: Color = .white
    
    // Mesh Gradient
    var meshGradientConfig: MeshGradientConfig = MeshGradientPreset.presets.first?.config ?? .default
    var selectedMeshPreset: MeshGradientPreset? = MeshGradientPreset.presets.first
    
    // Background Effects
    var backgroundNoise: Double = 0 // 0-100
    var backgroundBlur: Double = 0 // 0-100
    
    // Shadow Scene
    var shadowSceneMode: ShadowSceneMode = .underlay
    var shadowSceneOpacity: Double = 80
    
    // Text Overlays
    var textOverlays: [TextOverlay] = []
    
    // Redact/Blur regions (for sensitive text)
    var redactEnabled: Bool = false
    var redactStyle: RedactStyle = .blur
    var redactRegions: [RedactRegion] = []
    
    // Social Media Export
    var selectedSocialPreset: SocialMediaPreset? = nil
    
    // Canvas
    var padding: CGFloat = 80
    var zoom: CGFloat = 100
    
    // Export Scale (moved to transform section in UI)
    var scale: CGFloat = 1.0
    
    static let `default` = ScreenshotStyleConfig()
}
