import Foundation
import os

nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clicke", category: "Capture")

// MARK: - Screen Capturer

/// Runs `/usr/sbin/screencapture` without blocking the main thread.
///
/// Each capture is written to a unique private temporary file (never to the clipboard, which
/// belongs to the user), decoded in memory, then the file is deleted.
enum ScreenCapturer {
    enum CaptureError: LocalizedError {
        case launchFailed(Error)
        case screencaptureFailed(status: Int32)
        case unreadableImage

        var errorDescription: String? {
            switch self {
            case .launchFailed(let error):
                return String(localized: "The capture tool couldn't be started (\(error.localizedDescription)).")
            case .screencaptureFailed(let status):
                return String(localized: "The capture tool failed (code \(status)).")
            case .unreadableImage:
                return String(localized: "The captured image couldn't be read.")
            }
        }
    }

    private nonisolated static let executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

    /// Captures the screen in `mode`.
    /// - Returns: The decoded capture, or `nil` when the user cancelled (Esc): no file is written then.
    static func capture(_ mode: CaptureMode) async throws -> DecodedCapture? {
        let outputURL = try CaptureTemporaryStorage.makeCaptureFileURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let result: ProcessResult
        do {
            result = try await run(arguments: mode.screencaptureArguments + [outputURL.path])
        } catch {
            throw CaptureError.launchFailed(error)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            // Esc exits without a file. A message on stderr means a real failure (e.g. no permission).
            if result.status != 0, !result.errorOutput.isEmpty {
                logger.error("screencapture exited with status \(result.status, privacy: .public): \(result.errorOutput, privacy: .private)")
                throw CaptureError.screencaptureFailed(status: result.status)
            }
            return nil
        }

        guard let decoded = await CaptureImageIO.decodeCapture(at: outputURL) else {
            throw CaptureError.unreadableImage
        }
        return decoded
    }

    // MARK: Process

    private struct ProcessResult: Sendable {
        let status: Int32
        let errorOutput: String
    }

    /// Launches `screencapture` and suspends until it exits (the main thread stays responsive).
    private nonisolated static func run(arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            let errorPipe = Pipe()
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: ProcessResult(status: process.terminationStatus, errorOutput: output))
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
