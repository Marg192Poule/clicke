import SwiftUI

enum SettingsTab: String, CaseIterable {
    case settings = "Settings"
    case history = "History"
    case about = "About"
    
    var icon: String {
        switch self {
        case .settings: return "gearshape"
        case .history: return "clock"
        case .about: return "info.circle"
        }
    }
}

struct AppSettingsView: View {
    @State private var selectedTab: SettingsTab = .settings
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedTab) {
                Button {
                    selectedTab = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .tag(SettingsTab.settings)
                
                Button {
                    selectedTab = .history
                } label: {
                    Label("History", systemImage: "clock")
                }
                .buttonStyle(.plain)
                .tag(SettingsTab.history)
                
                Button {
                    selectedTab = .about
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
                .tag(SettingsTab.about)
            }
            .frame(minWidth: 200)
        } detail: {
            Group {
                switch selectedTab {
                case .settings:
                    SettingsContentView()
                        .navigationTitle("Preferences")
                case .history:
                    HistoryContentView()
                        .navigationTitle("History")
                case .about:
                    AboutContentView()
                        .navigationTitle("About")
                }
            }
            .frame(minWidth: 400, minHeight: 600)
        }
    }
}

