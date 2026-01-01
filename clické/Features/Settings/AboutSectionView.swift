import SwiftUI

struct AboutSectionView: View {
    var body: some View {
        Section {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
            
            HStack {
                Label("BetterShot", systemImage: "camera.viewfinder")
                Spacer()
                Text("BetterShot")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("About")
        }
    }
}

