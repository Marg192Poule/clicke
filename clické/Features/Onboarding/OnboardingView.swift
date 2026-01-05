import SwiftUI
import AppKit

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Dark background with gradient
            LinearGradient(
                colors: [
                    Color(white: 0.08),
                    Color(white: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Header with logo
                VStack(spacing: 16) {
                    // Logo
                    if let logoImage = NSImage(named: "AppIcon") {
                        Image(nsImage: logoImage)
                            .resizable()
                            .frame(width: 80, height: 80)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    }
                    
                    Text("Permissions Required")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Clické needs permissions to run properly.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 60)
                
                // Permissions list
                VStack(spacing: 16) {
                    // Screen Recording Permission
                    PermissionCard(
                        title: "Screen Recording Permission",
                        description: "This permission is required to capture screenshots.",
                        icon: "photo.on.rectangle.angled",
                        status: viewModel.screenRecordingStatus,
                        action: {
                            viewModel.requestScreenRecording()
                        }
                    )
                    
                    // Accessibility Permission
                    PermissionCard(
                        title: "Accessibility Permission",
                        description: "Required for keyboard shortcuts and window detection.",
                        icon: "accessibility",
                        status: viewModel.accessibilityStatus,
                        action: {
                            viewModel.requestAccessibility()
                        }
                    )
                }
                .padding(.horizontal, 50)
                
                Spacer()
                
                // Launch at login toggle
                HStack(spacing: 12) {
                    Toggle(isOn: $viewModel.launchAtLogin) {
                        HStack(spacing: 8) {
                            Image(systemName: "power")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                            Text("Launch at Login")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(.blue)
                }
                .padding(.horizontal, 50)
                .padding(.bottom, 20)
                
                // Continue button
                Button(action: {
                    viewModel.completeOnboarding()
                    dismiss()
                }) {
                    Text("Continue")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(viewModel.canContinue ? 1.0 : 0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(viewModel.canContinue ? 0.15 : 0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canContinue)
                .padding(.horizontal, 50)
                .padding(.bottom, 50)
            }
        }
        .frame(width: 600, height: 700)
        .onAppear {
            viewModel.checkPermissions()
        }
    }
}

struct PermissionCard: View {
    let title: String
    let description: String
    let icon: String
    let status: PermissionStatus
    let action: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // Status button
            statusButton
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        )
        .overlay(
            // Glass effect
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        )
    }
    
    @ViewBuilder
    private var statusButton: some View {
        switch status {
        case .granted:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Granted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
            )
            
        case .denied, .notDetermined:
            Button(action: action) {
                Text("Request Permission")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    OnboardingView()
}
