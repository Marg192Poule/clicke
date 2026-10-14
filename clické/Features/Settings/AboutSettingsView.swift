import SwiftUI
import AppKit

// MARK: - About

/// About tab: app icon, name, version, project link and license.
struct AboutSettingsView: View {
    private static let repositoryURL = URL(string: "https://github.com/nathbns/clicke")

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)

            Text(verbatim: "Clické")
                .font(.title)
                .fontWeight(.semibold)
                .padding(.top, 8)

            Text("Version \(Self.version) (\(Self.build))")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)

            Text("Capture screenshots from the menu bar and style them in seconds.")
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            if let url = Self.repositoryURL {
                Link(destination: url) {
                    Text(verbatim: "github.com/nathbns/clicke")
                }
                .padding(.top, 6)
            }

            VStack(spacing: 2) {
                Text("MIT License")
                Text(Self.copyright)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 18)
        }
        .padding(.horizontal, 40)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    // MARK: Bundle Info

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private static var copyright: String {
        if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
           !copyright.isEmpty {
            return copyright
        }
        return String(localized: "Copyright © 2025–2026 Nathan Ben Soussan")
    }
}
