import CoreGraphics
import Foundation
import os
import Vision

/// A piece of sensitive text found in an image.
nonisolated struct SensitiveTextMatch: Equatable, Sendable {
    let kind: SensitiveTextKind
    /// Padded bounding box of the text, in image pixel space with a top-left origin.
    let rect: CGRect
}

/// Finds sensitive text (emails, phone numbers, keys…) in an image.
///
/// Text recognition runs entirely on device with Vision; nothing is sent over the network.
nonisolated enum SensitiveTextDetector {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "clicke", category: "Redaction")

    /// Recognizes the text in `image` and returns the areas that look sensitive, off the main actor.
    @concurrent
    static func detect(in image: CGImage) async throws -> [SensitiveTextMatch] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        try Task.checkCancellation()

        let observations = request.results ?? []
        let imageSize = CGSize(width: image.width, height: image.height)
        var matches: [SensitiveTextMatch] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            for match in SensitiveTextPatterns.matches(in: candidate.string) {
                // Fall back to the whole line if Vision can't locate the substring: over-redacting
                // is safer than missing it.
                let box = (try? candidate.boundingBox(for: match.range))?.boundingBox ?? observation.boundingBox
                if let rect = paddedPixelRect(fromNormalized: box, imageSize: imageSize) {
                    matches.append(SensitiveTextMatch(kind: match.kind, rect: rect))
                }
            }
        }

        // Counts only: recognized text is never logged.
        logger.info("Found \(matches.count) sensitive items in \(observations.count) lines of text")
        return matches
    }

    /// Converts a normalized Vision box (bottom-left origin) to a padded pixel rectangle
    /// (top-left origin), clamped to the image.
    static func paddedPixelRect(fromNormalized box: CGRect, imageSize: CGSize) -> CGRect? {
        let rect = CGRect(
            x: box.minX * imageSize.width,
            y: (1 - box.maxY) * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
        )
        let padding = max(3, rect.height * 0.2)
        let padded = rect.insetBy(dx: -padding, dy: -padding).integral
            .intersection(CGRect(origin: .zero, size: imageSize))
        guard !padded.isNull, padded.width >= 1, padded.height >= 1 else { return nil }
        return padded
    }
}
