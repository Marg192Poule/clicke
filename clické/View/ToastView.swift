import SwiftUI

/// The HUD shown by `ToastManager`: an icon and a short message on Liquid Glass.
struct ToastView: View {
    /// Already-localized message (shown verbatim).
    let message: String
    /// SF Symbol name.
    let icon: String
    let success: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(success ? Color.primary : Color.red)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        // Room for the glass edge highlight and shadow inside the borderless panel.
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}
