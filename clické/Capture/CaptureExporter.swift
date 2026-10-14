import AppKit
import UniformTypeIdentifiers
import os

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clicke", category: "Export")

// MARK: - Capture Exporter

/// Copies captures to the clipboard and writes them to disk.
enum CaptureExporter {
    /// Puts the capture on the general pasteboard as PNG (preferred, compact) and TIFF (for apps
    /// that only read TIFF). Both keep transparency and the Retina point size.
    static func copyToPasteboard(_ capture: ScreenCapture) async {
        let tiffData = await CaptureImageIO.tiffData(
            for: SendableImage(cgImage: capture.cgImage),
            pointSize: capture.image.size
        )

        let item = NSPasteboardItem()
        item.setData(capture.pngData, forType: .png)
        if let tiffData {
            item.setData(tiffData, forType: .tiff)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.writeObjects([item]) {
            logger.error("Couldn't write the capture to the pasteboard")
        }
    }

    /// Saves the capture in `folder` under its default name, never overwriting an existing file
    /// ("Clické … (2).png", "… (3).png", …). Creates the folder if needed.
    /// - Returns: The URL of the written file.
    static func autoSave(_ capture: ScreenCapture, in folder: URL) async throws -> URL {
        try await writeUniqueFile(capture.pngData, baseName: capture.baseFileName, in: folder)
    }

    /// Asks where to save the capture (default name and folder from Settings), then writes it.
    /// - Parameter completion: Called with `true` once saved, `false` if cancelled or failed.
    static func presentSavePanel(for capture: ScreenCapture, completion: @escaping (Bool) -> Void) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Save Capture")
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
                ToastManager.shared.show(message: String(localized: "Saved"), icon: "checkmark.circle.fill", success: true)
                completion(true)
            } catch {
                logger.error("Couldn't save the capture: \(error.localizedDescription, privacy: .private)")
                presentSaveError()
                completion(false)
            }
        }
    }

    /// Reports a failed save with a toast.
    static func presentSaveError() {
        ToastManager.shared.show(
            message: String(localized: "Couldn't Save the Capture"),
            icon: "exclamationmark.triangle.fill",
            success: false
        )
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
