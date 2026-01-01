import SwiftUI

// mockup
enum MockupStyle: String, CaseIterable {
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

// theme
enum FrameColorScheme: String, CaseIterable, Identifiable {
    case dark
    case light
    
    var id: String { rawValue }
}

//border
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

// shadow
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

// background
enum BackgroundStyle: String, CaseIterable, Identifiable {
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

// preset color
struct Preset: Identifiable, Equatable {
    let id = UUID()
    let colors: [Color]
    let isPremium: Bool
    
    static let presets: [Preset] = [
        // neutral
        Preset(colors: [Color("ffffff")], isPremium: false),
        Preset(colors: [Color("2d2d2d")], isPremium: false),
        Preset(colors: [Color("8b7355"), Color("d4c4a8")], isPremium: false),
        Preset(colors: [Color("4a6572"), Color("8fb3c9")], isPremium: false),
        
        // cold
        Preset(colors: [Color("f5f5f5")], isPremium: false),
        Preset(colors: [Color("ffd93d"), Color("ff6b6b")], isPremium: false),
        Preset(colors: [Color("c9b037"), Color("6b5b3b")], isPremium: false),
        Preset(colors: [Color("667eea"), Color("764ba2")], isPremium: false),
        
        // warm
        Preset(colors: [Color("f0e6d3")], isPremium: false),
        Preset(colors: [Color("ff9a56"), Color("ff6b95")], isPremium: false),
        Preset(colors: [Color("a8edea"), Color("fed6e3")], isPremium: false),
        Preset(colors: [Color("11998e"), Color("38ef7d")], isPremium: false),
        
        // dark
        Preset(colors: [Color("1a1a2e")], isPremium: false),
        Preset(colors: [Color("f953c6"), Color("b91d73")], isPremium: false),
        Preset(colors: [Color("4facfe"), Color("00f2fe")], isPremium: false),
        Preset(colors: [Color("ee0979"), Color("ff6a00")], isPremium: false),
    ]
}

// shadow scene
struct ShadowScene: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let colors: [Color]
    let isTexture: Bool
    
    static let scenes: [ShadowScene] = [
        ShadowScene(name: "Cream", colors: [Color("f5e6d3"), Color("e8d4b8")], isTexture: true),
        ShadowScene(name: "Sand", colors: [Color("d4b896"), Color("c4a576")], isTexture: true),
        ShadowScene(name: "Paper", colors: [Color("f8f8f8"), Color("e8e8e8")], isTexture: true),
        ShadowScene(name: "Light Wood", colors: [Color("deb887"), Color("c4a574")], isTexture: true),
        ShadowScene(name: "Birch", colors: [Color("f5deb3"), Color("daa520")], isTexture: true),
        ShadowScene(name: "Plant", colors: [Color("90a955"), Color("4f772d")], isTexture: true),
        ShadowScene(name: "Concrete", colors: [Color("95a5a6"), Color("7f8c8d")], isTexture: true),
        ShadowScene(name: "Pine", colors: [Color("d2b48c"), Color("bc9b6a")], isTexture: true),
        ShadowScene(name: "Marble", colors: [Color("ecf0f1"), Color("bdc3c7")], isTexture: true),
        ShadowScene(name: "Oak", colors: [Color("8b4513"), Color("654321")], isTexture: true),
        ShadowScene(name: "Slate", colors: [Color("708090"), Color("4a5568")], isTexture: true),
        ShadowScene(name: "Walnut", colors: [Color("5d4037"), Color("3e2723")], isTexture: true),
        ShadowScene(name: "Black Marble", colors: [Color("2c3e50"), Color("1a252f")], isTexture: true),
        ShadowScene(name: "Grunge", colors: [Color("3d3d3d"), Color("1a1a1a")], isTexture: true),
        ShadowScene(name: "Metal", colors: [Color("4a4a4a"), Color("2d2d2d")], isTexture: true),
        ShadowScene(name: "Gold", colors: [Color("ffd700"), Color("b8860b")], isTexture: true),
    ]
}

// solid color
struct SolidColor: Identifiable, Equatable {
    let id = UUID()
    let color: Color
    
    static let colors: [SolidColor] = [
        SolidColor(color: Color("f8f9fa")),
        SolidColor(color: Color("343a40")),
        SolidColor(color: Color("adb5bd")),
        SolidColor(color: Color("dee2e6")),
    ]
}

// preset gradient
struct GradientPreset: Identifiable, Equatable {
    let id = UUID()
    let colors: [Color]
    let angle: Double
    
    static let presets: [GradientPreset] = [
        GradientPreset(colors: [Color("ff6b6b"), Color("feca57")], angle: 135),
        GradientPreset(colors: [Color("667eea"), Color("764ba2")], angle: 135),
        GradientPreset(colors: [Color("a8edea"), Color("fed6e3")], angle: 135),
        GradientPreset(colors: [Color("11998e"), Color("38ef7d")], angle: 135),
        GradientPreset(colors: [Color("fc466b"), Color("3f5efb")], angle: 135),
        GradientPreset(colors: [Color("00c6fb"), Color("005bea")], angle: 135),
        GradientPreset(colors: [Color("f093fb"), Color("f5576c")], angle: 135),
        GradientPreset(colors: [Color("4facfe"), Color("00f2fe")], angle: 135),
    ]
}

// export preset
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

// config style
struct ScreenshotStyleConfig: Equatable {
    // Mockup
    var mockupStyle: MockupStyle = .defaultStyle
    var showMockup: Bool = true
    var mockupBorderSize: CGFloat = 3
    
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
    var selectedShadowScene: ShadowScene? = nil
    var selectedSolidColor: SolidColor? = nil
    var selectedGradient: GradientPreset? = nil
    var backgroundImageURL: URL? = nil
    var customColor: Color = .white
    
    // Social Media Export
    var selectedSocialPreset: SocialMediaPreset? = nil
    
    // Canvas
    var padding: CGFloat = 80
    var zoom: CGFloat = 100
    
    // Export
    var scale: CGFloat = 1.0
    
    static let `default` = ScreenshotStyleConfig()
}
