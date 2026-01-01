import SwiftUI
import AppKit
import ApplicationServices

struct PermissionsSectionView: View {
    @Binding var showAlert: Bool
    
    var body: some View {
        Section {
            HStack(spacing: 12) {
                permissionCard(
                    title: "Accessibility",
                    icon: "accessibility",
                    status: checkAccessibilityPermissions(),
                    action: {
                        openAccessibilitySettings()
                    }
                )
            }
            
            if !checkAccessibilityPermissions() {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Accessibility is required for BetterShot to listen to your keyboard shortcut.")
                            .font(.callout)
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                    
                    Button {
                        openAccessibilitySettings()
                    } label: {
                        Text("Open Accessibility Settings")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        } header: {
            Text("Permissions")
        }
    }
    
    @ViewBuilder
    private func permissionCard(
        title: String,
        icon: String,
        status: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            
            Spacer()
            
            if status {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)
            } else {
                Button("Autoriser") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

