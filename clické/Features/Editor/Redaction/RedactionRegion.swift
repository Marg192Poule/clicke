import CoreGraphics
import Foundation

// MARK: - Style

/// How a redaction region hides the pixels underneath it.
nonisolated enum RedactionStyle: String, CaseIterable, Identifiable, Sendable {
    case pixelate
    case blur
    case solid

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .solid: "Solid"
        }
    }

    var systemImage: String {
        switch self {
        case .pixelate: "mosaic"
        case .blur: "drop.halffull"
        case .solid: "rectangle.fill"
        }
    }

    /// Whether the strength setting affects this style.
    var usesStrength: Bool { self != .solid }
}

// MARK: - Fill

/// Color used by the solid style.
nonisolated enum RedactionFill: String, CaseIterable, Identifiable, Sendable {
    case black
    case white
    case gray

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .black: "Black"
        case .white: "White"
        case .gray: "Gray"
        }
    }

    /// Gray level from 0 (black) to 1 (white).
    var whiteLevel: CGFloat {
        switch self {
        case .black: 0
        case .white: 1
        case .gray: 0.55
        }
    }

    var cgColor: CGColor {
        CGColor(srgbRed: whiteLevel, green: whiteLevel, blue: whiteLevel, alpha: 1)
    }
}

// MARK: - Tool Settings

/// Style applied to newly drawn or detected regions.
nonisolated struct RedactionToolSettings: Equatable, Sendable {
    var style: RedactionStyle = .pixelate
    /// Effect strength from 0 to 1. Defaults high so pixelated text stays unreadable.
    var strength: Double = 0.8
    var fill: RedactionFill = .black
}

// MARK: - Region

/// A rectangle of the image to hide, with its own style.
nonisolated struct RedactionRegion: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Rectangle in the image's pixel space, with the origin at the top-left corner.
    var rect: CGRect
    var style: RedactionStyle
    /// Effect strength from 0 to 1 (pixelate and blur only).
    var strength: Double
    var fill: RedactionFill

    init(id: UUID = UUID(), rect: CGRect, settings: RedactionToolSettings) {
        self.id = id
        self.rect = rect
        self.style = settings.style
        self.strength = settings.strength
        self.fill = settings.fill
    }

    var settings: RedactionToolSettings {
        RedactionToolSettings(style: style, strength: strength, fill: fill)
    }

    /// Regions in the order they are composited: effects first, then solid fills on top,
    /// so a blur or pixelation drawn later can never re-expose a filled area.
    static func compositingOrder(_ regions: [RedactionRegion]) -> [RedactionRegion] {
        regions.filter { $0.style != .solid } + regions.filter { $0.style == .solid }
    }
}
