import AppKit
import ImageIO
import UniformTypeIdentifiers
import os

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clicke", category: "Capture")

// MARK: - Capture Controller

/// Runs captures and everything that follows them (sound, clipboard, auto-save, preview/editor),
/// and opens images coming from Finder, the clipboard or the last capture.
final class CaptureController {
    static let shared = CaptureController()

    /// The most recent successful capture ("Edit Last Screenshot"): its PNG and thumbnail only.
    private(set) var lastCapture: ScreenCapture?

    /// `true` while `screencapture` is running: new triggers are ignored meanwhile.
    private(set) var isCapturing = false

    private init() {}

    // MARK: Capture

    /// Starts a capture, unless one is already running.
    func capture(_ mode: CaptureMode) {
        guard !isCapturing else {
            logger.info("Ignoring capture request: a capture is already running")
            return
        }
        // Without the permission, `screencapture` would only see the wallpaper and the menu bar.
        guard ScreenRecordingPermission.isGranted else {
            ScreenRecordingPermission.handleMissingAccess()
            return
        }
        isCapturing = true

        Task {
            defer { isCapturing = false }
            await performCapture(mode)
        }
    }

    private func performCapture(_ mode: CaptureMode) async {
        do {
            guard let decoded = try await ScreenCapturer.capture(mode) else {
                // Cancelled with Esc, or macOS denied the capture without a message (permission revoked).
                if !ScreenRecordingPermission.isGranted {
                    ScreenRecordingPermission.handleMissingAccess()
                }
                return
            }
            await finish(decoded)
        } catch {
            logger.error("Capture failed: \(error.localizedDescription, privacy: .private)")
            if !ScreenRecordingPermission.isGranted {
                ScreenRecordingPermission.handleMissingAccess()
            } else {
                ToastManager.shared.show(
                    message: String(localized: "Couldn’t Capture the Screen"),
                    icon: "exclamationmark.triangle.fill",
                    success: false
                )
            }
        }
    }

    /// Applies the user's after-capture settings.
    private func finish(_ decoded: DecodedCapture) async {
        let capture = ScreenCapture(decoded: decoded)
        lastCapture = capture
        let settings = AppSettings.current

        if settings.soundEffectsEnabled {
            SoundManager.shared.playSound(settings.captureSound, volume: Float(settings.soundEffectsVolume))
        }

        var copied = false
        if settings.copyToClipboard {
            copied = CaptureExporter.copyToPasteboard(capture)
            if !copied {
                ToastManager.shared.show(
                    message: String(localized: "Couldn’t Copy the Screenshot"),
                    icon: "exclamationmark.triangle.fill",
                    success: false
                )
            }
        }

        switch settings.afterCaptureAction {
        case .showPreview:
            CapturePreviewController.shared.show(capture)
        case .openEditor:
            // The bitmap was just decoded: hand it over instead of decoding the PNG again.
            ScreenshotEditorWindow.shared.show(with: decoded.makeImage())
        case .nothing:
            break
        }

        var savedFolder: URL?
        if settings.autoSaveCaptures {
            let folder = settings.saveDirectoryURL
            do {
                savedFolder = try await CaptureExporter.autoSave(capture, in: folder).deletingLastPathComponent()
            } catch {
                logger.error("Auto-save failed: \(error.localizedDescription, privacy: .private)")
                CaptureExporter.presentFolderSaveFailure(folder: folder)
                return
            }
        }

        // Without a preview or the editor, a toast is the only sign that something happened.
        if settings.afterCaptureAction == .nothing {
            confirmSilentCapture(copied: copied, savedFolder: savedFolder)
        }
    }

    private func confirmSilentCapture(copied: Bool, savedFolder: URL?) {
        let message: String
        let icon: String
        switch (copied, savedFolder) {
        case (true, let folder?):
            let folderName = CaptureExporter.displayName(of: folder)
            message = String(localized: "Copied and Saved to “\(folderName)”", comment: "Toast after a capture: folder name")
            icon = "checkmark.circle.fill"
        case (true, nil):
            message = String(localized: "Copied to Clipboard")
            icon = "doc.on.clipboard.fill"
        case (false, let folder?):
            message = CaptureExporter.savedMessage(folder: folder)
            icon = "checkmark.circle.fill"
        case (false, nil):
            return
        }
        ToastManager.shared.show(message: message, icon: icon, success: true)
    }

    // MARK: Opening Images

    /// Opens the most recent capture in the editor.
    func editLastCapture() {
        guard let lastCapture else { return }
        guard let image = lastCapture.makeImage() else {
            showOpenError(String(localized: "Couldn’t Open the Screenshot"))
            return
        }
        ScreenshotEditorWindow.shared.show(with: image)
    }

    /// Whether the clipboard holds image data (checks the types only, doesn't read the contents).
    var clipboardHasImage: Bool {
        NSPasteboard.general.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
    }

    /// Opens the clipboard image in the editor. An image file copied in Finder opens the file
    /// itself (Finder also puts the file's icon on the clipboard, which isn't what the user wants).
    ///
    /// Nothing is decoded here: the editor decodes (and bounds) the image when it builds the layer.
    func editClipboardImage() {
        let pasteboard = NSPasteboard.general
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]

        if let fileURL = (pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL])?.first {
            openImages(at: [fileURL])
        } else if let image = NSImage(pasteboard: pasteboard), Self.hasContent(image) {
            ScreenshotEditorWindow.shared.show(with: image)
        } else {
            showOpenError(String(localized: "No Image on the Clipboard"), icon: "doc.on.clipboard")
        }
    }

    /// Opens image files in the editor (the first opens it, the next ones are added as layers).
    /// Files that aren't images are rejected with a message.
    func openImages(at urls: [URL]) {
        var images: [NSImage] = []
        var failures: [String] = []

        for url in urls where url.isFileURL {
            let name = FileManager.default.displayName(atPath: url.path)
            guard Self.isImageFile(url) else {
                logger.error("Not opening a file that isn't an image")
                failures.append(String(localized: "“\(name)” Isn’t an Image", comment: "Toast: a file that isn't an image was opened"))
                continue
            }
            // `NSImage(contentsOf:)` reads the file but decodes the pixels only when they're first used.
            guard let image = NSImage(contentsOf: url), Self.hasContent(image) else {
                logger.error("Couldn't open an image file")
                failures.append(String(localized: "Couldn’t Open “\(name)”", comment: "Toast: an image file couldn't be read"))
                continue
            }
            images.append(image)
        }

        if !images.isEmpty {
            ScreenshotEditorWindow.shared.show(with: images)
        }
        if let failure = failures.first {
            showOpenError(failures.count == 1 ? failure : String(localized: "Some Files Couldn’t Be Opened"))
        }
    }

    /// Shows an Open panel for images, then opens the selection in the editor.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open Image")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.openImages(at: panel.urls)
        }
    }

    // MARK: Helpers

    /// Whether `url` is an image file ImageIO can read, judging from its type and header only.
    private static func isImageFile(_ url: URL) -> Bool {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetType(source) != nil,
           CGImageSourceGetCount(source) > 0 {
            return true
        }
        // Formats only `NSImage` reads (e.g. SVG).
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        return type?.conforms(to: .image) == true
    }

    /// Whether `image` has something to draw, without decoding its pixels (unlike `isValid`).
    private static func hasContent(_ image: NSImage) -> Bool {
        !image.representations.isEmpty && image.size.width > 0 && image.size.height > 0
    }

    private func showOpenError(_ message: String, icon: String = "exclamationmark.triangle.fill") {
        ToastManager.shared.show(message: message, icon: icon, success: false)
    }
}
