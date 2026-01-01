import SwiftUI

// classic toast
struct ToastView: View {
    let message: String
    let icon: String 
    let success: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))

                Text(message)
                    .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular)
    }
}

// toast with edit button
struct InteractiveToastView: View {
    let message: String
    let icon: String
    let onEdit: () -> Void

    @State private var isHovered = false 

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // Edit button
            Button(action: onEdit) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Edit")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(isHovered ? 0.1 : 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular)
    }
}