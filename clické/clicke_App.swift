import SwiftUI

@main
struct clicke_App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            EmptyView() // Empty so this is only a menu bar app
        }
    }
}
