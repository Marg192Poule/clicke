import SwiftUI

// MARK: - Color from Hex

extension Color {
    /// Creates a color from a hexadecimal string ("fff", "ffffff" or "ffffffff", with or without "#").
    init(hex: String) {
        self = RGBAColor(hex: hex).color
    }
}

// MARK: - RGBA Bindings

extension Binding where Value == RGBAColor {
    /// Bridges a stored `RGBAColor` to the `Color` expected by `ColorPicker`.
    var color: Binding<Color> {
        Binding<Color>(
            get: { wrappedValue.color },
            set: { wrappedValue = RGBAColor($0) }
        )
    }
}

// MARK: - Editor Interaction

/// Lets controls tell the editor that a continuous edit (e.g. a slider drag) begins or ends,
/// so the whole gesture becomes a single undo step.
struct EditorInteraction {
    var begin: () -> Void = {}
    var end: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var editorInteraction = EditorInteraction()
}
