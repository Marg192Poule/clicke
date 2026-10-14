import Foundation
import os

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clicke", category: "TemporaryFiles")

// MARK: - Temporary Storage

/// Private temporary files: raw `screencapture` output and PNG files handed out by drag and drop.
///
/// Everything lives in a per-app folder inside the user's temporary directory (`$TMPDIR`,
/// readable only by the user). Capture files are deleted as soon as they're decoded; drag files
/// must outlive the drop (the receiving app may read them later), so they're removed after an hour
/// and the whole folder is wiped at launch.
enum CaptureTemporaryStorage {
    private static let dragFileLifetime: TimeInterval = 60 * 60

    private static var rootURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Clicke", isDirectory: true)
    }

    private static var capturesURL: URL { rootURL.appendingPathComponent("Captures", isDirectory: true) }
    private static var dragURL: URL { rootURL.appendingPathComponent("Drag", isDirectory: true) }

    /// A new, unique path for `screencapture` to write to.
    static func makeCaptureFileURL() throws -> URL {
        try createPrivateDirectory(at: capturesURL)
        return capturesURL.appendingPathComponent(UUID().uuidString, isDirectory: false).appendingPathExtension("png")
    }

    /// Writes `data` to a temporary file named `fileName` (in its own folder, so the name stays
    /// readable for the receiving app) and returns its URL.
    static func writeDragFile(_ data: Data, named fileName: String) throws -> URL {
        removeStaleDragFiles()
        let folder = dragURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try createPrivateDirectory(at: folder)
        let url = folder.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Removes every temporary file (called at launch to clean up after a previous session).
    static func removeAll() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        do {
            try fileManager.removeItem(at: rootURL)
        } catch {
            logger.error("Couldn't remove temporary files: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: Private

    private static func removeStaleDragFiles() {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: dragURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let limit = Date().addingTimeInterval(-dragFileLifetime)
        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < limit {
                try? fileManager.removeItem(at: folder)
            }
        }
    }

    private static func createPrivateDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
