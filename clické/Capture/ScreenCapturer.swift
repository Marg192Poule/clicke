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
                return String(localized: "The capture tool couldn’t be started (\(error.localizedDescription)).")
            case .screencaptureFailed(let status):
                return String(localized: "The capture tool failed (code \(status)).")
            case .unreadableImage:
                return String(localized: "The captured image couldn’t be read.")
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
        /// The end of what `screencapture` wrote to stderr (for logging and failure detection).
        let errorOutput: String
    }

    /// Launches `screencapture` and suspends until it exits (the main thread stays responsive).
    ///
    /// stderr is drained while the process runs: a pipe holds 64 KB, and a process writing more
    /// than that to a pipe nobody reads blocks forever (so it would never exit). Only the last few
    /// kilobytes are kept.
    private nonisolated static func run(arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice

            let errorPipe = Pipe()
            let errorHandle = errorPipe.fileHandleForReading
            let errorTail = OutputTail()
            process.standardError = errorPipe

            errorHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil   // end of file
                } else {
                    errorTail.append(chunk)
                }
            }

            process.terminationHandler = { process in
                // Whatever is left in the pipe now fits in its buffer: reading it can't block for long.
                errorHandle.readabilityHandler = nil
                errorTail.append((try? errorHandle.readToEnd()) ?? Data())
                continuation.resume(returning: ProcessResult(status: process.terminationStatus, errorOutput: errorTail.text))
            }

            do {
                try process.run()
            } catch {
                errorHandle.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Output Tail

/// The last bytes written by a process, filled from a background queue.
private nonisolated final class OutputTail: @unchecked Sendable {
    private static let limit = 8 * 1024

    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.withLock {
            data.append(chunk)
            if data.count > Self.limit {
                data = Data(data.suffix(Self.limit))
            }
        }
    }

    var text: String {
        lock.withLock {
            String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
