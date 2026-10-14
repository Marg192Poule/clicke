import Foundation
import os

/// Editor preferences stored in UserDefaults: the last used style (so the next capture opens
/// with the same look) and the export format.
enum EditorPreferences {
    /// The persisted look: canvas style + the style applied to new layers.
    struct SavedStyle: Codable, Equatable {
        var canvas: ScreenshotStyleConfig
        var layer: LayerStyle
    }

    private static let styleKey = "EditorLastStyle"
    private static let exportFormatKey = "EditorExportFormat"
    private static let jpegQualityKey = "EditorJPEGQuality"
    private static let inspectorTabKey = "EditorInspectorTab"

    private static var defaults: UserDefaults { .standard }

    // MARK: Style

    /// The last saved style, or `nil` on first launch (or if it couldn't be read).
    static func loadStyle() -> SavedStyle? {
        guard let data = defaults.data(forKey: styleKey) else { return nil }
        do {
            return try JSONDecoder().decode(SavedStyle.self, from: data)
        } catch {
            Logger.editor.error("Couldn't read the saved editor style: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    static func saveStyle(_ style: SavedStyle) {
        do {
            defaults.set(try JSONEncoder().encode(style), forKey: styleKey)
        } catch {
            Logger.editor.error("Couldn't save the editor style: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: Export

    static var exportFormat: ExportFormat {
        get { defaults.string(forKey: exportFormatKey).flatMap(ExportFormat.init(rawValue:)) ?? .png }
        set { defaults.set(newValue.rawValue, forKey: exportFormatKey) }
    }

    /// JPEG quality, 0–1.
    static var jpegQuality: Double {
        get { defaults.object(forKey: jpegQualityKey) as? Double ?? 0.9 }
        set { defaults.set(newValue, forKey: jpegQualityKey) }
    }

    // MARK: Inspector

    static var inspectorTab: InspectorTab {
        get { defaults.string(forKey: inspectorTabKey).flatMap(InspectorTab.init(rawValue:)) ?? .background }
        set { defaults.set(newValue.rawValue, forKey: inspectorTabKey) }
    }
}

/// The inspector's pages.
enum InspectorTab: String, CaseIterable, Identifiable {
    case style
    case background
    case canvas

    var id: String { rawValue }
}

extension Logger {
    /// Logs of the screenshot editor.
    nonisolated static let editor = Logger(subsystem: Bundle.main.bundleIdentifier ?? "clicke", category: "Editor")
}
