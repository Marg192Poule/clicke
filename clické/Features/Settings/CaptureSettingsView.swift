import SwiftUI
import AppKit
import CoreGraphics

// MARK: - Capture Settings

/// Capture tab: what happens after a capture, clipboard, auto-save folder and Screen Recording permission.
struct CaptureSettingsView: View {
    @Bindable var model: SettingsModel

    @State private var hasScreenRecordingAccess = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section {
                Picker(selection: $model.settings.afterCaptureAction) {
                    ForEach(AfterCaptureAction.allCases) { action in
                        Text(action.preferencesTitle).tag(action)
                    }
                } label: {
                    Text("After capture")
                    Text(model.settings.afterCaptureAction.preferencesSummary)
                }

                Toggle("Copy to clipboard", isOn: $model.settings.copyToClipboard)
            }

            Section {
                Toggle("Save captures automatically", isOn: $model.settings.autoSaveCaptures)
                SaveFolderRow(model: model)
            } footer: {
                if capturesAreDiscarded {
                    Label(
                        "Captures won’t be kept. Turn on “Copy to clipboard” or “Save captures automatically”.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .symbolRenderingMode(.multicolor)
                }
            }

            Section("Permissions") {
                ScreenRecordingPermissionRow(hasAccess: hasScreenRecordingAccess)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onAppearAndAppActivation(perform: refreshPermissionStatus)
    }

    /// With "Do Nothing" and neither clipboard nor auto-save, a capture would go nowhere.
    private var capturesAreDiscarded: Bool {
        let settings = model.settings
        return settings.afterCaptureAction == .nothing && !settings.copyToClipboard && !settings.autoSaveCaptures
    }

    private func refreshPermissionStatus() {
        hasScreenRecordingAccess = CGPreflightScreenCaptureAccess()
    }
}

// MARK: - After Capture Action Text

fileprivate extension AfterCaptureAction {
    /// Menu item title.
    var preferencesTitle: LocalizedStringResource {
        switch self {
        case .showPreview: "Show Preview"
        case .openEditor: "Open Editor"
        case .nothing: "Do Nothing"
        }
    }

    /// One-line description shown under the picker.
    var preferencesSummary: LocalizedStringResource {
        switch self {
        case .showPreview: "Shows a floating preview with quick actions."
        case .openEditor: "Opens the capture in the editor right away."
        case .nothing: "Captures are only copied or saved, as set below."
        }
    }
}

// MARK: - Save Folder Row

/// Shows the folder used for saved captures, with buttons to change it or open it in Finder.
private struct SaveFolderRow: View {
    @Bindable var model: SettingsModel

    var body: some View {
        let url = model.settings.saveDirectoryURL
        let exists = folderExists(at: url)

        LabeledContent {
            HStack(spacing: 8) {
                Button("Show in Finder") {
                    NSWorkspace.shared.open(url)
                }
                .disabled(!exists)

                Button("Choose…") {
                    chooseFolder(startingAt: url)
                }
            }
        } label: {
            Label {
                Text(FileManager.default.displayName(atPath: url.path))
                if exists {
                    Text(verbatim: (url.path as NSString).abbreviatingWithTildeInPath)
                } else {
                    Text("This folder can’t be found.")
                }
            } icon: {
                Image(nsImage: folderIcon(for: url, exists: exists))
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            .help((url.path as NSString).abbreviatingWithTildeInPath)
        }
    }

    /// The folder's Finder icon, or a generic folder icon when it's missing.
    private func folderIcon(for url: URL, exists: Bool) -> NSImage {
        if !exists, let genericFolder = NSImage(named: NSImage.folderName) {
            return genericFolder
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func folderExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func chooseFolder(startingAt url: URL) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose where Clické saves your captures.")

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let chosen = panel.url else { return }
            model.settings.saveDirectoryPath = chosen.path
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }
}

// MARK: - Screen Recording Permission Row

/// Screen Recording status, with a shortcut to System Settings when access is missing.
private struct ScreenRecordingPermissionRow: View {
    let hasAccess: Bool

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    var body: some View {
        LabeledContent {
            if hasAccess {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Allowed")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Open System Settings…") {
                    requestAccess()
                }
            }
        } label: {
            Text("Screen Recording")
            if hasAccess {
                Text("Clické can capture the contents of your screen.")
            } else {
                Text("Clické needs this permission to capture your screen. After allowing it, macOS may ask you to reopen Clické.")
            }
        }
    }

    private func requestAccess() {
        // Registers Clické in the Screen Recording list (and shows the system prompt the first time).
        CGRequestScreenCaptureAccess()
        if let url = Self.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
