import SwiftUI
import AppKit

// MARK: - Capture Settings

/// Capture tab: what happens after a capture, clipboard, auto-save folder and Screen Recording permission.
struct CaptureSettingsView: View {
    @Bindable var model: SettingsModel

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
                Toggle("Save screenshots automatically", isOn: $model.settings.autoSaveCaptures)
                SaveFolderRow(model: model)
            } footer: {
                if screenshotsAreDiscarded {
                    Label(
                        "Screenshots won’t be kept. Turn on “Copy to clipboard” or “Save screenshots automatically”.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .symbolRenderingMode(.multicolor)
                }
            }

            Section("Permissions") {
                ScreenRecordingPermissionRow(hasAccess: model.hasScreenRecordingAccess)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// With "Do Nothing" and neither clipboard nor auto-save, a screenshot would go nowhere.
    private var screenshotsAreDiscarded: Bool {
        let settings = model.settings
        return settings.afterCaptureAction == .nothing && !settings.copyToClipboard && !settings.autoSaveCaptures
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
        case .openEditor: "Opens the screenshot in the editor right away."
        case .nothing: "Screenshots are only copied or saved, as set below."
        }
    }
}

// MARK: - Save Folder Row

/// "Save to" row: the folder used for saved screenshots, with buttons to reveal it in Finder or change it.
private struct SaveFolderRow: View {
    @Bindable var model: SettingsModel

    var body: some View {
        let url = model.settings.saveDirectoryURL
        let exists = folderExists(at: url)
        let path = (url.path as NSString).abbreviatingWithTildeInPath

        LabeledContent {
            HStack(spacing: 8) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .disabled(!exists)

                Button("Choose…") {
                    chooseFolder(startingAt: url)
                }
            }
        } label: {
            Text("Save to")
            if exists {
                Text(verbatim: path)
                    .help(path)
            } else {
                Text("“\(FileManager.default.displayName(atPath: url.path))” can’t be found. Choose another folder.")
                    .help(path)
            }
        }
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
        panel.message = String(localized: "Choose where Clické saves your screenshots.")

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

/// Screen Recording status, with a button to ask for access when it's missing.
private struct ScreenRecordingPermissionRow: View {
    let hasAccess: Bool

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
                // The first click shows the system prompt; later clicks open the Screen & System Audio
                // Recording pane of System Settings. The status is re-read when the window becomes key again.
                Button("Open System Settings") {
                    ScreenRecordingPermission.requestAccess()
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
}
