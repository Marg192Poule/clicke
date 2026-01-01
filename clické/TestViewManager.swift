import SwiftUI

struct TestManagersView: View {
    let toastManager = ToastManager()
    let hotkeyManager = HotkeyManager()
    
    var body: some View {
        VStack(spacing: 20) {
            // Test ToastManager
            Button("Test Toast Success") {
                toastManager.show(message: "Success!", icon: "checkmark.circle", success: true)
            }
            
            Button("Test Toast Error") {
                toastManager.show(message: "Error!", icon: "xmark.circle", success: false)
            }
            
            // Test HotkeyManager
            Button("Register Hotkey (Cmd+Shift+X)") {
                hotkeyManager.setHotkeyHandler {
                    print("Hotkey pressed!")
                    toastManager.show(message: "Hotkey triggered!", icon: "⌨️", success: true)
                }
                hotkeyManager.registerHotkey()
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}