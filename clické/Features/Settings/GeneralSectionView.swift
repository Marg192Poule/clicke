import SwiftUI

struct AppearanceSectionView: View {
    @Binding var showDockIcon: Bool
    
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("show dock icon", isOn: $showDockIcon)
                }
            } icon: {
                Image(systemName: "dock.rectangle")
            }
        } header: {
            Text("general")
        }
    }
}

struct GeneralSectionView: View {
    @Binding var copyToClipboard: Bool
    
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("copy to clipboard", isOn: $copyToClipboard)
                }
            } icon: {
                Image(systemName: "doc.on.clipboard")
            }
        } header: {
            Text("general")
        }
    }
}

