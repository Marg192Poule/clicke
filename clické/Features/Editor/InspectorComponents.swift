import SwiftUI

// MARK: - Slider Row

/// How a slider value is displayed.
enum SliderUnit {
    case none
    case points
    case percent
    /// A 0–1 value shown as a percentage.
    case fraction
    case degrees

    func format(_ value: Double) -> String {
        switch self {
        case .none: "\(Int(value.rounded()))"
        case .points: "\(Int(value.rounded())) pt"
        case .percent: "\(Int(value.rounded()))%"
        case .fraction: "\(Int((value * 100).rounded()))%"
        case .degrees: "\(Int(value.rounded()))°"
        }
    }
}

/// A labeled slider with its value, updating the canvas live while dragging.
/// Right-click offers "Reset" when a default value is given.
///
/// It takes a plain value and a setter (not a binding) and is `Equatable` on its inputs, so with
/// `.equatable()` a slider only redraws when its own value changes: dragging one slider doesn't
/// redraw the others. The setter must not depend on anything else that changes (give the section
/// an `.id` when it edits a different layer).
struct InspectorSlider: View, Equatable {
    let title: LocalizedStringKey
    let value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var unit: SliderUnit = .none
    var defaultValue: Double?
    let onChange: (Double) -> Void

    @Environment(\.editorInteraction) private var interaction

    init(
        _ title: LocalizedStringKey,
        value: Double,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        unit: SliderUnit = .none,
        defaultValue: Double? = nil,
        onChange: @escaping (Double) -> Void
    ) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.defaultValue = defaultValue
        self.onChange = onChange
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.value == rhs.value && lhs.range == rhs.range
            && lhs.step == rhs.step && lhs.unit == rhs.unit && lhs.defaultValue == rhs.defaultValue
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                slider
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(unit.format(value))
                Text(unit.format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 42, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        } label: {
            Text(title)
        }
        .contextMenu {
            if let defaultValue {
                Button("Reset") {
                    interaction.begin()
                    onChange(defaultValue)
                    interaction.end()
                }
                .disabled(value == defaultValue)
            }
        }
    }

    @ViewBuilder
    private var slider: some View {
        let binding = Binding(get: { value }, set: onChange)
        if let step {
            Slider(value: binding, in: range, step: step, onEditingChanged: editingChanged)
        } else {
            Slider(value: binding, in: range, onEditingChanged: editingChanged)
        }
    }

    private func editingChanged(_ isEditing: Bool) {
        isEditing ? interaction.begin() : interaction.end()
    }
}

// MARK: - Selectable Tile

/// A visual choice (style, wallpaper, preset…) with an accent selection ring and hover feedback.
struct SelectableTile<Content: View>: View {
    let title: Text
    let isSelected: Bool
    var cornerRadius: CGFloat = 6
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            content()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(outlineOpacity), lineWidth: 1)
                }
                .padding(3)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Stronger with Increase Contrast, so light tiles stay distinct from the inspector.
    private var outlineOpacity: Double {
        switch (contrast == .increased, isHovering) {
        case (true, true): 0.7
        case (true, false): 0.45
        case (false, true): 0.35
        case (false, false): 0.12
        }
    }
}

/// A tile with a caption underneath.
struct CaptionedTile<Content: View>: View {
    let title: Text
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 3) {
            SelectableTile(title: title, isSelected: isSelected, action: action, content: content)
            title
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Color Swatch

/// A round color choice.
struct ColorSwatchButton: View {
    let color: RGBAColor
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let isIncreased = contrast == .increased
        Button(action: action) {
            Circle()
                .fill(color.color)
                .overlay(Circle().strokeBorder(Color.primary.opacity(isHovering ? (isIncreased ? 0.7 : 0.4) : (isIncreased ? 0.45 : 0.15)), lineWidth: 1))
                .padding(3)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(Text(verbatim: color.accessibilityName.prefix(1).localizedUppercase + color.accessibilityName.dropFirst()))
        .accessibilityLabel(Text("Color"))
        .accessibilityValue(Text(color.accessibilityName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension RGBAColor {
    /// A short description for VoiceOver ("Blue", "Light Gray"…), from AppKit's color naming.
    var accessibilityName: String {
        nsColor.accessibilityName
    }
}
