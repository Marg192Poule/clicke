import AppKit
import UniformTypeIdentifiers
import os

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clicke", category: "Capture")

// MARK: - Capture Controller

/// Runs captures and everything that follows them (sound, clipboard, auto-save, preview/editor),
/// and opens images coming from Finder, the clipboard or the last capture.
final class CaptureController {
    static let shared = CaptureController()

    /// The most recent successful capture ("Edit Last Capture").
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
        isCapturing = true

        Task {
            defer { isCapturing = false }
            await performCapture(mode)
        }
    }

    private func performCapture(_ mode: CaptureMode) async {
        do {
            guard let decoded = try await ScreenCapturer.capture(mode) else {
                // Cancelled with Esc, or macOS denied the capture without a message.
                if !ScreenRecordingPermission.isGranted {
                    ScreenRecordingPermission.presentGuidance()
                }
                return
            }
            await finish(ScreenCapture(decoded: decoded))
        } catch {
            logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            if !ScreenRecordingPermission.isGranted {
                ScreenRecordingPermission.presentGuidance()
            } else {
                ToastManager.shared.show(
                    message: String(localized: "Couldn't Capture the Screen"),
                    icon: "exclamationmark.triangle.fill",
                    success: false
                )
            }
        }
    }

    /// Applies the user's after-capture settings.
    private func finish(_ capture: ScreenCapture) async {
        lastCapture = capture
        let settings = AppSettings.current

        if settings.soundEffectsEnabled {
            SoundManager.shared.playSound(settings.captureSound, volume: Float(settings.soundEffectsVolume))
        }

        switch settings.afterCaptureAction {
        case .showPreview:
            CapturePreviewController.shared.show(capture)
        case .openEditor:
            ScreenshotEditorWindow.shared.show(with: capture.image)
        case .nothing:
            break
        }

        if settings.copyToClipboard {
            await CaptureExporter.copyToPasteboard(capture)
        }

        if settings.autoSaveCaptures {
            do {
                _ = try await CaptureExporter.autoSave(capture, in: settings.saveDirectoryURL)
            } catch {
                logger.error("Auto-save failed: \(error.localizedDescription, privacy: .private)")
                CaptureExporter.presentSaveError()
            }
        }
    }

    // MARK: Opening Images

    /// Opens the most recent capture in the editor.
    func editLastCapture() {
        guard let lastCapture else { return }
        ScreenshotEditorWindow.shared.show(with: lastCapture.image)
    }

    /// Whether the clipboard holds image data (checks the types only, doesn't read the contents).
    var clipboardHasImage: Bool {
        NSPasteboard.general.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
    }

    /// Opens the clipboard image in the editor. An image file copied in Finder opens the file
    /// itself (Finder also puts the file's icon on the clipboard, which isn't what the user wants).
    func editClipboardImage() {
        let pasteboard = NSPasteboard.general
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]

        if let fileURL = (pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL])?.first,
           let image = NSImage(contentsOf: fileURL), image.isValid {
            ScreenshotEditorWindow.shared.show(with: image)
        } else if let image = NSImage(pasteboard: pasteboard), image.isValid {
            ScreenshotEditorWindow.shared.show(with: image)
        } else {
            ToastManager.shared.show(
                message: String(localized: "No Image on the Clipboard"),
                icon: "doc.on.clipboard",
                success: false
            )
        }
    }

    /// Opens image files in the editor (the first opens it, the next ones are added as layers).
    func openImages(at urls: [URL]) {
        for url in urls where url.isFileURL {
            if let image = NSImage(contentsOf: url), image.isValid {
                ScreenshotEditorWindow.shared.show(with: image)
            } else {
                logger.error("Couldn't open an image file")
                ToastManager.shared.show(
                    message: String(localized: "Couldn't Open “\(url.lastPathComponent)”"),
                    icon: "exclamationmark.triangle.fill",
                    success: false
                )
            }
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
}
