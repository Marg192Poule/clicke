//
//  ContentView.swift
//  clické
//
//  Created by Nathan Ben Soussan on 31/12/2025.
//

import SwiftUI

struct ContentView: View {
    let toastManager = ToastManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Test Managers")
                .font(.title)
            
            Button("Test Toast") {
                toastManager.show(
                    message: "Hello Toast!", 
                    icon: "checkmark.circle", 
                    success: true
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
