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
}

// MARK: - Device Frame
enum DeviceFrame: String, CaseIterable, Identifiable {
    case none
    case macWindow
    case browser
    case iphone
    case ipad
    case macbook
    case imac
    
    var id: String { rawValue }
}

// MARK: - Frame Color Scheme
enum FrameColorScheme: String, CaseIterable, Identifiable {
    case dark
    case light
    
    var id: String { rawValue }
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

// MARK: - Shadow Style (comme shots.so)
enum ShadowStyle: String, CaseIterable, Identifiable {
    case none
    case spread
    case hug
    case adaptive
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .spread: return "Spread"
        case .hug: return "Hug"
        case .adaptive: return "Adaptiv"
        }
    }
}

// MARK: - Background Type
enum BackgroundType: String, CaseIterable, Identifiable {
    case transparent
    case color
    case image
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .transparent: return "Transparent"
        case .color: return "Color"
        case .image: return "Image"
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
    
    // Device Frame
    var deviceFrame: DeviceFrame = .none
    var showDeviceFrame: Bool = false
    var frameColorScheme: FrameColorScheme = .dark
    
    // Border
    var borderStyle: BorderStyle = .curved
    var borderRadius: CGFloat = 20
    
    // Shadow
    var shadowStyle: ShadowStyle = .spread
    var shadowOpacity: Double = 40
    
    // Transform
    var rotation: Double = 0
    var imageScale: CGFloat = 100 // Scale of the screenshot itself (100 = 100%)
    var screenshotOffset: CGSize = .zero // Offset to move screenshot within the canvas
    
    // Background
    var backgroundType: BackgroundType = .color
    var selectedMagicPreset: MagicPreset? = MagicPreset.presets[7] // Default purple gradient
    var selectedShadowScene: ShadowScene? = nil
    var selectedSolidColor: SolidColor? = nil
    var selectedGradient: GradientPreset? = nil
    var backgroundImageURL: URL? = nil
    var customColor: Color = .white
    
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
    
    // Export
    var scale: CGFloat = 1.0
    
    static let `default` = ScreenshotStyleConfig()
}
