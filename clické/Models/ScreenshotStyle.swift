import SwiftUI
import AppKit

// MARK: - RGBA Color

/// A Codable sRGB color. SwiftUI's `Color` isn't Codable nor reliably comparable,
/// so every color that is part of the style (and therefore persisted / diffed) uses this type.
nonisolated struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Creates a color from a hex string ("fff", "ffffff" or "ffffffff", with or without "#").
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: Double(a) / 255)
    }

    /// Converts any SwiftUI color (e.g. coming from a `ColorPicker`) to sRGB components.
    init(_ color: Color) {
        self.init(NSColor(color))
    }

    init(_ nsColor: NSColor) {
        let srgb = nsColor.usingColorSpace(.sRGB) ?? .black
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)
}

// MARK: - Background Type

/// The kind of background drawn behind the screenshots.
nonisolated enum BackgroundType: String, Codable, CaseIterable, Identifiable {
    case transparent
    case color
    case gradient
    case image

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .transparent: "Transparent"
        case .color: "Color"
        case .gradient: "Gradient"
        case .image: "Image"
        }
    }
}

// MARK: - Solid Color Swatches

/// The solid colors offered as one-click swatches (a `ColorPicker` covers everything else).
nonisolated enum ColorSwatch {
    static let colors: [RGBAColor] = [
        RGBAColor(hex: "ffffff"),
        RGBAColor(hex: "f2f2f7"),
        RGBAColor(hex: "8e8e93"),
        RGBAColor(hex: "1c1c1e"),
        RGBAColor(hex: "000000"),
        RGBAColor(hex: "667eea"),
        RGBAColor(hex: "0a84ff"),
        RGBAColor(hex: "11998e"),
        RGBAColor(hex: "34c759"),
        RGBAColor(hex: "ffcc00"),
        RGBAColor(hex: "ff9500"),
        RGBAColor(hex: "f953c6"),
    ]
}

// MARK: - Gradient

/// The geometry of a gradient fill.
nonisolated enum GradientStyle: String, Codable, CaseIterable, Identifiable {
    case linear
    case radial
    case angular

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .linear: "Linear"
        case .radial: "Radial"
        case .angular: "Angular"
        }
    }
}

/// A two- or three-color gradient.
nonisolated struct GradientFill: Codable, Hashable, Sendable {
    var style: GradientStyle = .linear
    /// 2 or 3 color stops, evenly spaced.
    var colors: [RGBAColor] = [RGBAColor(hex: "667eea"), RGBAColor(hex: "764ba2"), RGBAColor(hex: "f953c6")]
    /// Direction of a linear gradient, in degrees (0 = bottom to top, 90 = left to right).
    var angle: Double = 135

    private var swiftUIColors: [Color] { colors.map(\.color) }

    private var startPoint: UnitPoint {
        let radians = (angle - 90) * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    private var endPoint: UnitPoint {
        let radians = (angle - 90) * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }

    /// The gradient as a view filling `size` (the size only matters for the radial radius).
    @MainActor @ViewBuilder
    func view(size: CGSize) -> some View {
        switch style {
        case .linear:
            LinearGradient(colors: swiftUIColors, startPoint: startPoint, endPoint: endPoint)
        case .radial:
            RadialGradient(colors: swiftUIColors, center: .center, startRadius: 0, endRadius: max(size.width, size.height) * 0.7)
        case .angular:
            AngularGradient(colors: swiftUIColors + [swiftUIColors.first ?? .clear], center: .center)
        }
    }
}

/// A named gradient offered as a one-click tile.
nonisolated struct GradientPreset: Identifiable {
    let name: String
    let fill: GradientFill

    var id: String { name }

    private init(_ name: String, _ hexes: [String], style: GradientStyle = .linear, angle: Double = 135) {
        self.name = name
        self.fill = GradientFill(style: style, colors: hexes.map(RGBAColor.init(hex:)), angle: angle)
    }

    static let presets: [GradientPreset] = [
        GradientPreset("Cinder", ["120806", "6b1f14"]),
        GradientPreset("Trench", ["050a14", "233a52"]),
        GradientPreset("Black Pine", ["070f0b", "2f5a45"]),
        GradientPreset("Obsidian Sand", ["0e0c0b", "6a5a4a"]),
        GradientPreset("Midnight Surge", ["020409", "0b1f2a", "1f4e5f"]),
        GradientPreset("Graphite", ["232526", "414345"]),
        GradientPreset("Dusk", ["667eea", "764ba2", "f953c6"]),
        GradientPreset("Sunset", ["ff7e5f", "feb47b"]),
        GradientPreset("Ocean", ["2193b0", "6dd5ed"]),
        GradientPreset("Aurora", ["11998e", "38ef7d"]),
        GradientPreset("Peach", ["ffecd2", "fcb69f"]),
        GradientPreset("Lavender", ["e0c3fc", "8ec5fc"]),
    ]
}

// MARK: - Background Image

/// Where a background image comes from. Bundled wallpapers are stored by base name (not by path)
/// so a persisted style survives app updates and asset format changes.
nonisolated enum BackgroundImageSource: Codable, Hashable, Sendable {
    /// A wallpaper shipped in the app bundle, identified by its file name without extension.
    case bundled(String)
    /// An image file picked by the user.
    case file(URL)

    /// The default wallpaper of a fresh install.
    static let defaultWallpaper = BackgroundImageSource.bundled("Black and White Gradient Macbook Wallpaper_Texture")

    static let imageExtensions = ["heic", "jpg", "jpeg", "png", "tiff", "webp"]

    /// The file URL to load, or `nil` if the image no longer exists.
    var url: URL? {
        switch self {
        case .bundled(let name):
            guard let resources = Bundle.main.resourceURL else { return nil }
            for folder in [resources.appendingPathComponent("public"), resources] {
                for ext in Self.imageExtensions {
                    let candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
                    if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                }
            }
            return nil
        case .file(let url):
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }
}

// MARK: - Background Effects

/// Effects applied to the background (never to the screenshots themselves).
nonisolated struct BackgroundEffects: Codable, Hashable, Sendable {
    /// Gaussian blur radius, in canvas points.
    var blur: Double = 0
    /// Film grain amount, 0–100.
    var grain: Double = 0
    /// Saturation, in percent (100 = unchanged).
    var saturation: Double = 100
    /// Brightness, in percent (100 = unchanged).
    var brightness: Double = 100

    var isDefault: Bool { self == BackgroundEffects() }
}

// MARK: - Canvas Size Presets

/// A fixed canvas size, mostly for social networks. Exports are exactly `width × height` pixels.
nonisolated struct SocialMediaPreset: Identifiable, Hashable, Sendable {
    let platform: String
    let name: String
    let width: Int
    let height: Int
    let ratio: String

    /// Stable identifier, used for persistence.
    var id: String { "\(platform).\(name)" }

    var aspectRatio: CGFloat { CGFloat(width) / CGFloat(height) }
    var size: CGSize { CGSize(width: width, height: height) }

    static let presets: [SocialMediaPreset] = [
        SocialMediaPreset(platform: "Twitter", name: "Post", width: 1200, height: 675, ratio: "16:9"),
        SocialMediaPreset(platform: "Twitter", name: "Header", width: 1500, height: 500, ratio: "3:1"),
        SocialMediaPreset(platform: "Instagram", name: "Square", width: 1080, height: 1080, ratio: "1:1"),
        SocialMediaPreset(platform: "Instagram", name: "Portrait", width: 1080, height: 1350, ratio: "4:5"),
        SocialMediaPreset(platform: "Instagram", name: "Story", width: 1080, height: 1920, ratio: "9:16"),
        SocialMediaPreset(platform: "LinkedIn", name: "Post", width: 1200, height: 627, ratio: "1.91:1"),
        SocialMediaPreset(platform: "LinkedIn", name: "Cover", width: 1584, height: 396, ratio: "4:1"),
        SocialMediaPreset(platform: "YouTube", name: "Thumbnail", width: 1280, height: 720, ratio: "16:9"),
        SocialMediaPreset(platform: "YouTube", name: "Banner", width: 2560, height: 1440, ratio: "16:9"),
        SocialMediaPreset(platform: "Dribbble", name: "Shot", width: 1600, height: 1200, ratio: "4:3"),
        SocialMediaPreset(platform: "Dribbble", name: "Tall", width: 1600, height: 2400, ratio: "2:3"),
        SocialMediaPreset(platform: "Pinterest", name: "Pin", width: 1000, height: 1500, ratio: "2:3"),
        SocialMediaPreset(platform: "Pinterest", name: "Long", width: 1000, height: 2100, ratio: "10:21"),
        SocialMediaPreset(platform: "Standard", name: "16:9", width: 1920, height: 1080, ratio: "16:9"),
        SocialMediaPreset(platform: "Standard", name: "4:3", width: 1920, height: 1440, ratio: "4:3"),
        SocialMediaPreset(platform: "Standard", name: "3:2", width: 1920, height: 1280, ratio: "3:2"),
        SocialMediaPreset(platform: "Standard", name: "1:1", width: 1080, height: 1080, ratio: "1:1"),
    ]

    static func preset(withID id: String?) -> SocialMediaPreset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }
}

// MARK: - Screenshot Style Configuration

/// Canvas-level style: background, effects and canvas size.
/// Per-layer appearance (frame, corners, shadow, transforms) lives in `LayerStyle` / `CanvasItem`.
nonisolated struct ScreenshotStyleConfig: Codable, Hashable, Sendable {
    var backgroundType: BackgroundType = .image
    var backgroundColor: RGBAColor = .white
    var gradient: GradientFill = GradientPreset.presets[0].fill
    var backgroundImage: BackgroundImageSource = .defaultWallpaper
    var effects = BackgroundEffects()

    /// Identifier of the selected `SocialMediaPreset`; `nil` ("Auto") = the canvas wraps the
    /// screenshot and exports at its native resolution.
    var canvasPresetID: String?
    /// Space around the screenshot, in canvas points.
    var padding: Double = 80

    static let `default` = ScreenshotStyleConfig()

    var canvasPreset: SocialMediaPreset? {
        get { SocialMediaPreset.preset(withID: canvasPresetID) }
        set { canvasPresetID = newValue?.id }
    }

    /// Whether the export has no transparent pixels (lets the encoder drop the alpha channel).
    var isOpaque: Bool { backgroundType != .transparent }

    init() {}

    // Tolerant decoding: a missing or unreadable key falls back to its default,
    // so adding a property never discards the user's saved style.
    private enum CodingKeys: String, CodingKey {
        case backgroundType, backgroundColor, gradient, backgroundImage, effects, canvasPresetID, padding
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScreenshotStyleConfig.default
        backgroundType = (try? c.decode(BackgroundType.self, forKey: .backgroundType)) ?? d.backgroundType
        backgroundColor = (try? c.decode(RGBAColor.self, forKey: .backgroundColor)) ?? d.backgroundColor
        gradient = (try? c.decode(GradientFill.self, forKey: .gradient)) ?? d.gradient
        backgroundImage = (try? c.decode(BackgroundImageSource.self, forKey: .backgroundImage)) ?? d.backgroundImage
        effects = (try? c.decode(BackgroundEffects.self, forKey: .effects)) ?? d.effects
        canvasPresetID = c.contains(.canvasPresetID) ? (try? c.decodeIfPresent(String.self, forKey: .canvasPresetID)) : d.canvasPresetID
        padding = (try? c.decode(Double.self, forKey: .padding)) ?? d.padding
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(backgroundType, forKey: .backgroundType)
        try c.encode(backgroundColor, forKey: .backgroundColor)
        try c.encode(gradient, forKey: .gradient)
        try c.encode(backgroundImage, forKey: .backgroundImage)
        try c.encode(effects, forKey: .effects)
        try c.encode(canvasPresetID, forKey: .canvasPresetID) // explicit null = "Auto"
        try c.encode(padding, forKey: .padding)
    }
}

// MARK: - Mockup Style

/// The frame drawn around a screenshot.
nonisolated enum MockupStyle: String, Codable, CaseIterable, Identifiable {
    case none
    case glass
    case border
    case window

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .none: "None"
        case .glass: "Glass"
        case .border: "Border"
        case .window: "Window"
        }
    }
}

/// Light or dark title bar for the macOS window mockup.
nonisolated enum WindowChromeAppearance: String, Codable, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

// MARK: - Layer Shadow

/// Drop shadow under a layer. Values are in the layer's own points (they scale with the layer).
nonisolated struct LayerShadow: Codable, Hashable, Sendable {
    var isEnabled = true
    var radius: Double = 30
    /// 0–1.
    var opacity: Double = 0.35
    var offsetY: Double = 16
}

// MARK: - Layer Style

/// Appearance of a single screenshot layer. The last used one is remembered for the next capture.
nonisolated struct LayerStyle: Codable, Hashable, Sendable {
    var mockup: MockupStyle = .none
    /// Thickness of the Glass / Border frame, in layer points.
    var frameWidth: Double = 9
    var borderColor = RGBAColor(hex: "2d2d2d")
    var windowAppearance: WindowChromeAppearance = .dark
    /// Corner radius of the screenshot, in layer points.
    var cornerRadius: Double = 20
    var shadow = LayerShadow()

    static let `default` = LayerStyle()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case mockup, frameWidth, borderColor, windowAppearance, cornerRadius, shadow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LayerStyle.default
        mockup = (try? c.decode(MockupStyle.self, forKey: .mockup)) ?? d.mockup
        frameWidth = (try? c.decode(Double.self, forKey: .frameWidth)) ?? d.frameWidth
        borderColor = (try? c.decode(RGBAColor.self, forKey: .borderColor)) ?? d.borderColor
        windowAppearance = (try? c.decode(WindowChromeAppearance.self, forKey: .windowAppearance)) ?? d.windowAppearance
        cornerRadius = (try? c.decode(Double.self, forKey: .cornerRadius)) ?? d.cornerRadius
        shadow = (try? c.decode(LayerShadow.self, forKey: .shadow)) ?? d.shadow
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mockup, forKey: .mockup)
        try c.encode(frameWidth, forKey: .frameWidth)
        try c.encode(borderColor, forKey: .borderColor)
        try c.encode(windowAppearance, forKey: .windowAppearance)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(shadow, forKey: .shadow)
    }

    // MARK: Frame Metrics

    /// Height of the window mockup's title bar, in layer points.
    static let windowTitleBarHeight: CGFloat = 28

    /// Space the frame adds around the image, in layer points.
    var chromeInsets: EdgeInsets {
        switch mockup {
        case .none:
            return EdgeInsets()
        case .glass, .border:
            let w = CGFloat(frameWidth)
            return EdgeInsets(top: w, leading: w, bottom: w, trailing: w)
        case .window:
            return EdgeInsets(top: Self.windowTitleBarHeight, leading: 0, bottom: 0, trailing: 0)
        }
    }

    /// The outer corner radius of the framed layer (concentric with the image corners).
    var outerCornerRadius: CGFloat {
        switch mockup {
        case .glass, .border: CGFloat(cornerRadius + frameWidth)
        case .none, .window: CGFloat(cornerRadius)
        }
    }

    /// Size of the framed layer for an image of `imageSize` points.
    func framedSize(for imageSize: CGSize) -> CGSize {
        let insets = chromeInsets
        return CGSize(
            width: imageSize.width + insets.leading + insets.trailing,
            height: imageSize.height + insets.top + insets.bottom
        )
    }
}

// MARK: - Canvas Item

/// A screenshot placed on the canvas, with its own style and transforms.
struct CanvasItem: Identifiable, Equatable {
    let id: UUID
    var image: LayerImage
    var style: LayerStyle

    /// Position of the layer's center relative to the canvas center, in canvas points.
    var offset: CGSize = .zero
    /// Size in percent (100 = natural size, or "fit" for fixed-size canvases).
    var scale: Double = 100
    /// 2D rotation, in degrees.
    var rotation: Double = 0
    /// 3D tilt around the horizontal / vertical axis, in degrees.
    var rotationX: Double = 0
    var rotationY: Double = 0
    /// Stacking order (higher is in front).
    var zIndex: Double = 0

    init(image: LayerImage, style: LayerStyle, id: UUID = UUID()) {
        self.id = id
        self.image = image
        self.style = style
    }

    /// Size of the framed layer before scaling, in layer points.
    var framedSize: CGSize { style.framedSize(for: image.pointSize) }
}

// MARK: - Export Format

/// File format used by Save and drag-out exports (the clipboard always gets PNG + TIFF).
nonisolated enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case png
    case jpeg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}
