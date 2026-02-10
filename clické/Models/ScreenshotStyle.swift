import SwiftUI
import AppKit

// MARK: - Mockup Style

/// Defines the visual style applied to the screenshot mockup.
enum MockupStyle: String, CaseIterable, Identifiable {
    case defaultStyle
    case glassEffect
    case border
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .defaultStyle: return "Default"
        case .glassEffect: return "Glass"
        case .border: return "Border"
        }
    }
}

// MARK: - Border Style

/// Defines the corner style for screenshot borders.
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

/// Defines the type of background for the screenshot canvas.
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

/// A solid color preset with optional premium status.
struct MagicPreset: Identifiable, Equatable {
    let id: UUID
    let colors: [Color]
    let isPremium: Bool
    
    init(colors: [Color], isPremium: Bool = false) {
        self.id = UUID()
        self.colors = colors
        self.isPremium = isPremium
    }
    
    // Cached presets - created once
    private static let _presets: [MagicPreset] = [
        MagicPreset(colors: [Color(hex: "ffffff")]),
        MagicPreset(colors: [Color(hex: "1a1a1a")]),
        MagicPreset(colors: [Color(hex: "667eea")]),
        MagicPreset(colors: [Color(hex: "f953c6")]),
        MagicPreset(colors: [Color(hex: "11998e")]),
    ]
    
    static var presets: [MagicPreset] { _presets }
}

// MARK: - Gradient Style

/// Defines the type of gradient effect.
enum GradientStyle: String, CaseIterable, Identifiable {
    case linear
    case radial
    case angular
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .radial: return "Radial"
        case .angular: return "Angular"
        }
    }
    
    var icon: String {
        switch self {
        case .linear: return "arrow.up.right"
        case .radial: return "circle.dashed"
        case .angular: return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Simple Gradient Configuration

/// Configuration for gradient backgrounds with effects.
struct SimpleGradientConfig: Equatable {
    var style: GradientStyle = .linear
    var color1: Color = Color(hex: "667eea")
    var color2: Color = Color(hex: "764ba2")
    var color3: Color = Color(hex: "f953c6")
    var useThreeColors: Bool = true
    var angle: Double = 135
    
    // Effects
    var blurAmount: Double = 0
    var noiseAmount: Double = 0
    var saturation: Double = 100
    var brightness: Double = 100
    
    static let `default` = SimpleGradientConfig()
    
    private var gradientColors: [Color] {
        useThreeColors ? [color1, color2, color3] : [color1, color3]
    }
    
    private var linearStartPoint: UnitPoint {
        let radians = (angle - 90) * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }
    
    private var linearEndPoint: UnitPoint {
        let radians = (angle - 90) * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }
    
    @ViewBuilder
    func gradientView(size: CGSize, isRendering: Bool = false) -> some View {
        gradientBase(size: size)
            .saturation(isRendering ? saturation / 100 : 1.0)
            .brightness(isRendering ? (brightness - 100) / 100 : 0.0)
            .colorAdjustments(
                saturation: isRendering ? 1.0 : saturation / 100,
                brightness: isRendering ? 0.0 : (brightness - 100) / 100
            )
            .frame(width: size.width, height: size.height)
    }
    
    @ViewBuilder
    func previewView(size: CGSize) -> some View {
        gradientBase(size: size)
            .frame(width: size.width, height: size.height)
    }
    
    @ViewBuilder
    private func gradientBase(size: CGSize) -> some View {
        switch style {
        case .linear:
            LinearGradient(colors: gradientColors, startPoint: linearStartPoint, endPoint: linearEndPoint)
        case .radial:
            RadialGradient(colors: gradientColors, center: .center, startRadius: 0, endRadius: max(size.width, size.height) * 0.7)
        case .angular:
            AngularGradient(colors: gradientColors + [gradientColors.first ?? color1], center: .center)
        }
    }
}

// MARK: - Grain/Noise Overlay

/// A view that applies a film grain noise effect.
struct GrainOverlay: View {
    let intensity: Double
    
    var body: some View {
        Rectangle()
            .fill(.white)
            .colorEffect(ShaderLibrary.noise(.float(intensity)))
            .allowsHitTesting(false)
            .blendMode(.overlay)
            .opacity(intensity * 0.5)
    }
}

// MARK: - Simple Gradient Presets

/// A pre-configured gradient preset.
struct SimpleGradientPreset: Identifiable, Equatable {
    let id: UUID
    let name: String
    let config: SimpleGradientConfig
    
    init(name: String, config: SimpleGradientConfig) {
        self.id = UUID()
        self.name = name
        self.config = config
    }
    
    static func == (lhs: SimpleGradientPreset, rhs: SimpleGradientPreset) -> Bool {
        lhs.id == rhs.id
    }
    
    private static let _presets: [SimpleGradientPreset] = [
        SimpleGradientPreset(name: "Cinder", config: SimpleGradientConfig(
            color1: Color(hex: "120806"), color2: Color(hex: "6b1f14"), color3: Color(hex: "6b1f14"), useThreeColors: false
        )),
        SimpleGradientPreset(name: "Trench", config: SimpleGradientConfig(
            color1: Color(hex: "050a14"), color2: Color(hex: "233a52"), color3: Color(hex: "233a52"), useThreeColors: false
        )),
        SimpleGradientPreset(name: "Black Pine", config: SimpleGradientConfig(
            color1: Color(hex: "070f0b"), color2: Color(hex: "2f5a45"), color3: Color(hex: "2f5a45"), useThreeColors: false
        )),
        SimpleGradientPreset(name: "Obsidian Sand", config: SimpleGradientConfig(
            color1: Color(hex: "0e0c0b"), color2: Color(hex: "6a5a4a"), color3: Color(hex: "6a5a4a"), useThreeColors: false
        )),
        SimpleGradientPreset(name: "Midnight Surge", config: SimpleGradientConfig(
            color1: Color(hex: "020409"), color2: Color(hex: "0b1f2a"), color3: Color(hex: "1f4e5f"), useThreeColors: true
        )),
    ]
    
    static var presets: [SimpleGradientPreset] { _presets }
}

// MARK: - Text Overlay

/// A text element that can be placed on the screenshot.
struct TextOverlay: Identifiable, Equatable {
    let id = UUID()
    var text: String = "Text"
    var fontSize: CGFloat = 24
    var fontWeight: Font.Weight = .semibold
    var color: Color = .white
    var position: CGPoint = .zero
    var rotation: Double = 0
    var opacity: Double = 1.0
    var isBlurred: Bool = false
}

// MARK: - Redact Region

/// A region of the screenshot to be redacted/obscured.
struct RedactRegion: Identifiable, Equatable {
    let id = UUID()
    var rect: CGRect
    var style: RedactStyle = .blur
}

/// Defines the style of redaction to apply.
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

/// A preset for exporting screenshots to social media platforms.
struct SocialMediaPreset: Identifiable, Equatable {
    let id: UUID
    let platform: String
    let name: String
    let width: Int
    let height: Int
    let icon: String
    let ratio: String
    
    init(platform: String, name: String, width: Int, height: Int, icon: String, ratio: String) {
        self.id = UUID()
        self.platform = platform
        self.name = name
        self.width = width
        self.height = height
        self.icon = icon
        self.ratio = ratio
    }
    
    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(height)
    }
    
    private static let _presets: [SocialMediaPreset] = [
        SocialMediaPreset(platform: "Twitter", name: "Tweet", width: 1200, height: 675, icon: "bird", ratio: "16:9"),
        SocialMediaPreset(platform: "Twitter", name: "Cover", width: 1500, height: 500, icon: "bird", ratio: "3:1"),
        SocialMediaPreset(platform: "YouTube", name: "Thumbnail", width: 1280, height: 720, icon: "play.rectangle.fill", ratio: "16:9"),
        SocialMediaPreset(platform: "YouTube", name: "Banner", width: 2560, height: 1440, icon: "play.rectangle.fill", ratio: "16:9"),
        SocialMediaPreset(platform: "Instagram", name: "Post", width: 1080, height: 1080, icon: "camera", ratio: "1:1"),
        SocialMediaPreset(platform: "Instagram", name: "Portrait", width: 1080, height: 1350, icon: "camera", ratio: "4:5"),
        SocialMediaPreset(platform: "Instagram", name: "Story", width: 1080, height: 1920, icon: "camera", ratio: "9:16"),
        SocialMediaPreset(platform: "Pinterest", name: "Long", width: 1000, height: 2100, icon: "pin", ratio: "10:21"),
        SocialMediaPreset(platform: "Pinterest", name: "Optimal", width: 1000, height: 1500, icon: "pin", ratio: "2:3"),
        SocialMediaPreset(platform: "Pinterest", name: "Square", width: 1000, height: 1000, icon: "pin", ratio: "1:1"),
        SocialMediaPreset(platform: "Dribbble", name: "Shot", width: 1600, height: 1200, icon: "basketball", ratio: "4:3"),
        SocialMediaPreset(platform: "Dribbble", name: "Full", width: 1600, height: 2400, icon: "basketball", ratio: "2:3"),
        SocialMediaPreset(platform: "LinkedIn", name: "Post", width: 1200, height: 627, icon: "person.crop.rectangle", ratio: "1.91:1"),
        SocialMediaPreset(platform: "LinkedIn", name: "Cover", width: 1584, height: 396, icon: "person.crop.rectangle", ratio: "4:1"),
        SocialMediaPreset(platform: "Standard", name: "16:9", width: 1920, height: 1080, icon: "rectangle", ratio: "16:9"),
        SocialMediaPreset(platform: "Standard", name: "4:3", width: 1920, height: 1440, icon: "rectangle", ratio: "4:3"),
        SocialMediaPreset(platform: "Standard", name: "1:1", width: 1080, height: 1080, icon: "square", ratio: "1:1"),
        SocialMediaPreset(platform: "Standard", name: "3:2", width: 1920, height: 1280, icon: "rectangle", ratio: "3:2"),
    ]
    
    static var presets: [SocialMediaPreset] { _presets }
    
    static var groupedByPlatform: [String: [SocialMediaPreset]] {
        Dictionary(grouping: presets) { $0.platform }
    }
}

// MARK: - Screenshot Style Configuration

/// Complete configuration for screenshot styling and export.
struct ScreenshotStyleConfig: Equatable {
    // Mockup
    var mockupStyle: MockupStyle = .defaultStyle
    var showMockup: Bool = true
    var mockupBorderSize: CGFloat = 3
    var borderColor: Color = Color(hex: "2d2d2d")
    
    // Border
    var borderStyle: BorderStyle = .curved
    var borderRadius: CGFloat = 20
    
    // Transform
    var rotation: Double = 0
    var imageScale: CGFloat = 100
    var screenshotOffset: CGSize = .zero
    
    // 3D Transform
    var rotationX: Double = 0
    var rotationY: Double = 0
    var perspective: Double = 0
    
    // Background
    var backgroundType: BackgroundType = .image
    var selectedMagicPreset: MagicPreset? = nil
    var backgroundImageURL: URL? = nil
    var customColor: Color = .white
    
    // Simple Gradient
    var gradientConfig: SimpleGradientConfig = SimpleGradientPreset.presets.first?.config ?? .default
    var selectedGradientPreset: SimpleGradientPreset? = SimpleGradientPreset.presets.first
    
    // Text Overlays
    var textOverlays: [TextOverlay] = []
    
    // Redact/Blur regions
    var redactEnabled: Bool = false
    var redactStyle: RedactStyle = .blur
    var redactRegions: [RedactRegion] = []
    
    // Social Media Export (default: Tweet format)
    var selectedSocialPreset: SocialMediaPreset? = SocialMediaPreset.presets.first
    
    // Canvas
    var padding: CGFloat = 80
    var zoom: CGFloat = 100
    
    // Export Scale
    var scale: CGFloat = 1.0
    
    static let `default` = ScreenshotStyleConfig()
    
    // MARK: - Transform Hash
    
    /// Hash of transform properties for consolidated animations.
    var transformHash: Int {
        var hasher = Hasher()
        hasher.combine(rotation)
        hasher.combine(rotationX)
        hasher.combine(rotationY)
        hasher.combine(scale)
        hasher.combine(imageScale)
        hasher.combine(borderRadius)
        return hasher.finalize()
    }
    
    // MARK: - Render Hash
    
    /// Hash of properties that affect final render (for cache invalidation).
    var renderHash: Int {
        var hasher = Hasher()
        hasher.combine(mockupStyle)
        hasher.combine(mockupBorderSize)
        hasher.combine(borderRadius)
        hasher.combine(rotation)
        hasher.combine(rotationX)
        hasher.combine(rotationY)
        hasher.combine(scale)
        hasher.combine(imageScale)
        hasher.combine(backgroundType)
        hasher.combine(backgroundImageURL)
        hasher.combine(gradientConfig.style)
        hasher.combine(gradientConfig.angle)
        hasher.combine(gradientConfig.blurAmount)
        hasher.combine(gradientConfig.noiseAmount)
        hasher.combine(gradientConfig.saturation)
        hasher.combine(gradientConfig.brightness)
        hasher.combine(padding)
        hasher.combine(selectedSocialPreset?.id)
        hasher.combine(selectedMagicPreset?.id)
        hasher.combine(textOverlays.count)
        hasher.combine(redactRegions.count)
        return hasher.finalize()
    }
    
    // MARK: - Equatable
    
    static func == (lhs: ScreenshotStyleConfig, rhs: ScreenshotStyleConfig) -> Bool {
        // Quick check with render hash first
        guard lhs.renderHash == rhs.renderHash else { return false }

        // Full comparison for remaining properties
        return lhs.mockupStyle == rhs.mockupStyle &&
               lhs.showMockup == rhs.showMockup &&
               lhs.mockupBorderSize == rhs.mockupBorderSize &&
               lhs.borderRadius == rhs.borderRadius &&
               lhs.rotation == rhs.rotation &&
               lhs.rotationX == rhs.rotationX &&
               lhs.rotationY == rhs.rotationY &&
               lhs.scale == rhs.scale &&
               lhs.imageScale == rhs.imageScale &&
               lhs.backgroundType == rhs.backgroundType &&
               lhs.backgroundImageURL == rhs.backgroundImageURL &&
               lhs.gradientConfig == rhs.gradientConfig &&
               lhs.padding == rhs.padding &&
               lhs.zoom == rhs.zoom &&
               lhs.screenshotOffset == rhs.screenshotOffset &&
               lhs.selectedSocialPreset?.id == rhs.selectedSocialPreset?.id
    }
}

// MARK: - Canvas Item

/// Represents a single image placed on the canvas with its own transforms.
struct CanvasItem: Identifiable, Equatable {
    let id: UUID
    var image: NSImage

    // Per-item transforms
    var offset: CGSize = .zero
    var scale: CGFloat = 1.0
    var imageScale: CGFloat = 100
    var rotation: Double = 0
    var rotationX: Double = 0
    var rotationY: Double = 0

    // Per-item appearance
    var borderRadius: CGFloat = 20
    var borderStyle: BorderStyle = .curved
    var mockupStyle: MockupStyle = .defaultStyle
    var showMockup: Bool = true
    var mockupBorderSize: CGFloat = 3
    var borderColor: Color = Color(hex: "2d2d2d")

    // Layer ordering
    var zIndex: Double = 0

    init(image: NSImage, id: UUID = UUID()) {
        self.id = id
        self.image = image
    }

    var transformHash: Int {
        var hasher = Hasher()
        hasher.combine(rotation)
        hasher.combine(rotationX)
        hasher.combine(rotationY)
        hasher.combine(scale)
        hasher.combine(imageScale)
        hasher.combine(borderRadius)
        return hasher.finalize()
    }

    static func == (lhs: CanvasItem, rhs: CanvasItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.offset == rhs.offset &&
        lhs.scale == rhs.scale &&
        lhs.imageScale == rhs.imageScale &&
        lhs.rotation == rhs.rotation &&
        lhs.rotationX == rhs.rotationX &&
        lhs.rotationY == rhs.rotationY &&
        lhs.borderRadius == rhs.borderRadius &&
        lhs.borderStyle == rhs.borderStyle &&
        lhs.mockupStyle == rhs.mockupStyle &&
        lhs.showMockup == rhs.showMockup &&
        lhs.mockupBorderSize == rhs.mockupBorderSize &&
        lhs.zIndex == rhs.zIndex
    }
}
