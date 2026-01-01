import SwiftUI

struct AppearanceSectionView: View {
    @Binding var showDockIcon: Bool
    
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Show Dock Icon", isOn: $showDockIcon)
                    Text("Show app icon in dock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: "dock.rectangle")
            }
        } header: {
            Text("Apparence")
        }
    }
}

struct GeneralSectionView: View {
    @Binding var copyToClipboard: Bool
    
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Copy to Clipboard", isOn: $copyToClipboard)
                    Text("Automatically copy the screenshot to the clipboard after capture")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: "doc.on.clipboard")
            }
        } header: {
            Text("General")
        }
    }
}

