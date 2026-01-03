import SwiftUI

struct AboutSectionView: View {
    var body: some View {
        Section {
            HStack {
                Label("version", systemImage: "info.circle")
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
            
            HStack {
                Label("app", systemImage: "camera.viewfinder")
                Spacer()
                Text("Clické")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("about")
        }
    }
}

