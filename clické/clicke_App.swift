//
//  clicke_App.swift
//  clické
//
//  Created by Nathan Ben Soussan on 31/12/2025.
//

import SwiftUI

@main
struct clicke_App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            EmptyView() // C'est empty pour que ce soit uniquement une menu tab app
        }
    }
}
