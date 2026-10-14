import AppKit
import UniformTypeIdentifiers
import os

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clicke", category: "Export")

// MARK: - Capture Exporter

/// Copies captures to the clipboard and writes them to disk.
enum CaptureExporter {
    /// The "Couldn’t Save" alert for the default folder is shown once per session (later failures
    /// show a toast), so a broken folder doesn't interrupt every capture.
    private static var hasPresentedFolderSaveAlert = false

    // MARK: Clipboard

    /// Puts the capture's PNG on the general pasteboard. TIFF, for the few apps that only read it,
    /// is only promised and encoded if an app asks for it (see `PasteboardWriter`).
    /// - Returns: `false` if the pasteboard refused the data.
    @discardableResult
    static func copyToPasteboard(_ capture: ScreenCapture) -> Bool {
        PasteboardWriter.writePNG(capture.pngData)
    }

    // MARK: Saving

    /// Saves the capture in `folder` under its default name, never overwriting an existing file
    /// ("Clické … (2).png", "… (3).png", …). Creates the folder if needed.
    /// - Returns: The URL of the written file.
    static func autoSave(_ capture: ScreenCapture, in folder: URL) async throws -> URL {
        try await writeUniqueFile(capture.pngData, baseName: capture.baseFileName, in: folder)
    }

    /// Saves the capture in the folder chosen in Settings and confirms it with a toast
    /// (preview menu's "Save to “Desktop”").
    /// - Returns: `true` once saved.
    static func saveToDefaultFolder(_ capture: ScreenCapture) async -> Bool {
        let folder = AppSettings.current.saveDirectoryURL
        do {
            _ = try await autoSave(capture, in: folder)
            ToastManager.shared.show(message: savedMessage(folder: folder), icon: "checkmark.circle.fill", success: true)
            return true
        } catch {
            logger.error("Couldn't save the capture: \(error.localizedDescription, privacy: .private)")
            presentFolderSaveFailure(folder: folder)
            return false
        }
    }

    /// Asks where to save the capture (default name and folder from Settings), then writes it.
    /// - Parameter completion: Called with `true` once saved, `false` if cancelled or failed.
    static func presentSavePanel(for capture: ScreenCapture, completion: @escaping (Bool) -> Void) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Save Screenshot")
        panel.nameFieldStringValue = capture.fileName
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = AppSettings.current.saveDirectoryURL

        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            do {
                try capture.pngData.write(to: url, options: .atomic)
                ToastManager.shared.show(
                    message: savedMessage(folder: url.deletingLastPathComponent()),
                    icon: "checkmark.circle.fill",
                    success: true
                )
                completion(true)
            } catch {
                logger.error("Couldn't save the capture: \(error.localizedDescription, privacy: .private)")
                ToastManager.shared.show(
                    message: String(localized: "Couldn’t Save the Screenshot"),
                    icon: "exclamationmark.triangle.fill",
                    success: false
                )
                completion(false)
            }
        }
    }

    /// Reports that saving to the Settings folder failed: an alert offering to choose another folder
    /// the first time in the session, a toast afterwards.
    static func presentFolderSaveFailure(folder: URL) {
        guard !hasPresentedFolderSaveAlert else {
            ToastManager.shared.show(
                message: String(localized: "Couldn’t Save the Screenshot"),
                icon: "exclamationmark.triangle.fill",
                success: false
            )
            return
        }
        hasPresentedFolderSaveAlert = true

        let folderName = displayName(of: folder)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn’t Save the Screenshot")
        alert.informativeText = String(localized: "Clické couldn’t save to “\(folderName)”. The folder may have been moved, or Clické may not have permission to write to it.")
        alert.addButton(withTitle: String(localized: "Choose Folder…"))
        alert.addButton(withTitle: String(localized: "OK"))

        ModalAlert.present(alert) { response in
            if response == .alertFirstButtonReturn {
                SettingsWindowController.shared.show(tab: .capture)
            }
        }
    }

    // MARK: Messages

    /// The folder's name as Finder shows it ("Desktop", localized).
    static func displayName(of folder: URL) -> String {
        FileManager.default.displayName(atPath: folder.path)
    }

    /// "Saved to “Desktop”".
    static func savedMessage(folder: URL) -> String {
        String(localized: "Saved to “\(displayName(of: folder))”", comment: "Toast after saving a screenshot: folder name")
    }

    // MARK: Private

    @concurrent
    private nonisolated static func writeUniqueFile(_ data: Data, baseName: String, in folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for attempt in 1...10_000 {
            let name = attempt == 1 ? "\(baseName).png" : "\(baseName) (\(attempt)).png"
            let url = folder.appendingPathComponent(name, isDirectory: false)
            do {
                // `.withoutOverwriting` makes the existence check and the write a single atomic step.
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch let error as NSError where isFileExistsError(error) {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    private nonisolated static func isFileExistsError(_ error: NSError) -> Bool {
        (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError)
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST))
    }
}
