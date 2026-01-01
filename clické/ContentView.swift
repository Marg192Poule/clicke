//
//  ContentView.swift
//  clické
//
//  Created by Nathan Ben Soussan on 31/12/2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    let toastManager = ToastManager()
    let hotkeyManager = HotkeyManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Test Managers")
                .font(.title)
            
            Button("Test Toast Simple") {
                toastManager.show(
                    message: "Hello Toast!", 
                    icon: "sparkle.text.clipboard.fill",
                    success: true
                )
            }
            .buttonStyle(.borderedProminent)
            
            Button("Test Toast avec Edit") {
                // Crée une image de test
                let testImage = NSImage(size: NSSize(width: 400, height: 300))
                testImage.lockFocus()
                NSColor.systemBlue.setFill()
                NSBezierPath(rect: NSRect(x: 0, y: 0, width: 400, height: 300)).fill()
                testImage.unlockFocus()
                
                toastManager.showWithEditOption(
                    message: "Screenshot saved!",
                    icon: "camera.aperture",
                    screenshotImage: testImage
                )
            }
            .buttonStyle(.bordered)
            
            Button("Register Hotkey (Cmd+Shift+5)") {
                hotkeyManager.setHotkeyHandler {
                    print("Hotkey triggered!")
                    toastManager.show(
                        message: "Hotkey pressed!",
                        icon: "keyboard",
                        success: true
                    )
                }
                hotkeyManager.registerHotkey()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
