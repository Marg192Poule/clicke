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
/// Recognized text is never logged.
nonisolated enum SensitiveTextDetector {

    /// A line of recognized text.
    struct Line: Sendable {
        /// The recognition candidates, most likely first.
        let candidates: [String]
        /// Unpadded bounding box, in image pixel space with a top-left origin.
        let rect: CGRect
    }

    /// Large images are also read in overlapping tiles, since text recognition misses or
    /// misreads small text when it processes a full Retina capture at once.
    static let tilingThreshold: CGFloat = 2000
    static let tileSide: CGFloat = 1600
    static let minimumTileOverlap: CGFloat = 400
    /// Recognition candidates checked per line, so a misread top candidate doesn't hide a match.
    private static let candidatesPerLine = 3
    /// Recognition passes run at the same time.
    private static let maximumConcurrentPasses = 3

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "clicke", category: "Redaction")

    // MARK: - Detection

    /// Recognizes the text in `image` and returns the areas that look sensitive, off the main actor.
    @concurrent
    static func detect(in image: CGImage) async throws -> [SensitiveTextMatch] {
        let imageSize = CGSize(width: image.width, height: image.height)
        let areas = recognitionAreas(for: imageSize)

        let found = try await withThrowingTaskGroup(of: [SensitiveTextMatch].self) { group in
            var pending = areas[...]
            var found: [SensitiveTextMatch] = []
            func startNextPass() {
                guard let area = pending.popFirst() else { return }
                group.addTask { try await scan(image, area: area) }
            }
            for _ in 0..<maximumConcurrentPasses { startNextPass() }
            while let matches = try await group.next() {
                found += matches
                startNextPass()
            }
            return found
        }

        let matches = merged(found)
        // Counts only: recognized text is never logged.
        logger.info("Found \(matches.count) sensitive items in \(areas.count) recognition passes")
        return matches
    }

    /// The parts of an image of `size` read separately: the whole image, plus overlapping tiles
    /// for large images. Rectangles are in pixels, with a top-left origin.
    static func recognitionAreas(for size: CGSize) -> [CGRect] {
        let whole = CGRect(origin: .zero, size: size)
        guard max(size.width, size.height) >= tilingThreshold else { return [whole] }
        let width = min(tileSide, size.width)
        let height = min(tileSide, size.height)
        let tiles = tileOrigins(along: size.height).flatMap { y in
            tileOrigins(along: size.width).map { x in CGRect(x: x, y: y, width: width, height: height) }
        }
        return [whole] + tiles
    }

    /// Evenly spaced tile positions covering `length`, overlapping by at least `minimumTileOverlap`.
    private static func tileOrigins(along length: CGFloat) -> [CGFloat] {
        guard length > tileSide else { return [0] }
        let count = Int(((length - minimumTileOverlap) / (tileSide - minimumTileOverlap)).rounded(.up))
        let step = (length - tileSide) / CGFloat(count - 1)
        return (0..<count).map { (CGFloat($0) * step).rounded() }
    }

    /// Recognizes the text in `area` of `image` and returns its sensitive parts.
    private static func scan(_ image: CGImage, area: CGRect) async throws -> [SensitiveTextMatch] {
        let imageSize = CGSize(width: image.width, height: image.height)
        let isWhole = area == CGRect(origin: .zero, size: imageSize)
        guard let pixels = isWhole ? image : image.cropping(to: area) else { return [] }

        let request = RecognitionRequest()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            do {
                try VNImageRequestHandler(cgImage: pixels, options: [:]).perform([request.request])
            } catch {
                // A cancelled request fails with a Vision error; report it as a cancellation.
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            request.cancel()
        }
        try Task.checkCancellation()

        var matches: [SensitiveTextMatch] = []
        var lines: [Line] = []
        for observation in request.request.results ?? [] {
            let candidates = observation.topCandidates(candidatesPerLine)
            for candidate in candidates {
                for match in SensitiveTextPatterns.matches(in: candidate.string) {
                    // Fall back to the whole line if Vision can't locate the substring: over-redacting
                    // is safer than missing it.
                    let box = (try? candidate.boundingBox(for: match.range))?.boundingBox ?? observation.boundingBox
                    let rect = pixelRect(fromNormalized: box, in: area)
                    if let rect = padded(rect, lineHeight: rect.height, imageSize: imageSize) {
                        matches.append(SensitiveTextMatch(kind: match.kind, rect: rect))
                    }
                }
            }
            lines.append(Line(candidates: candidates.map(\.string), rect: pixelRect(fromNormalized: observation.boundingBox, in: area)))
        }

        for block in privateKeyBlocks(in: lines) {
            if let rect = padded(block.rect, lineHeight: block.lineHeight, imageSize: imageSize) {
                matches.append(SensitiveTextMatch(kind: .accessToken, rect: rect))
            }
        }
        return matches
    }

    // MARK: - Private Key Blocks

    /// Areas covering whole private key blocks, from the `BEGIN` line to the `END` line.
    ///
    /// When one end isn't visible (cut off by the image), the block extends over the adjacent
    /// lines that look like key data.
    static func privateKeyBlocks(in lines: [Line]) -> [(rect: CGRect, lineHeight: CGFloat)] {
        let sorted = lines.sorted { $0.rect.minY < $1.rect.minY }
        var blocks: [(rect: CGRect, lineHeight: CGFloat)] = []

        for (index, line) in sorted.enumerated() {
            let isHeader = line.candidates.contains(where: SensitiveTextPatterns.isPrivateKeyHeader)
            let isFooter = !isHeader && line.candidates.contains(where: SensitiveTextPatterns.isPrivateKeyFooter)
            guard isHeader || isFooter else { continue }
            // Lines below a header, or above a footer, in reading order.
            let following = isHeader ? Array(sorted[(index + 1)...]) : Array(sorted[..<index].reversed())
            var block = line.rect

            for next in following {
                let gap = isHeader ? next.rect.minY - block.maxY : block.minY - next.rect.maxY
                // Skip lines beside the block (other columns, same row).
                guard gap > -line.rect.height / 2, isInSameColumn(next.rect, as: line.rect) else { continue }
                guard gap <= line.rect.height * 2.5 else { break }

                let closesBlock = next.candidates.contains(where: isHeader ? SensitiveTextPatterns.isPrivateKeyFooter : SensitiveTextPatterns.isPrivateKeyHeader)
                guard closesBlock || next.candidates.contains(where: SensitiveTextPatterns.isPrivateKeyBody) else { break }
                block = block.union(next.rect)
                if closesBlock { break }
            }

            // A header and its footer both produce the same block; keep one.
            if !blocks.contains(where: { $0.rect.contains(block) || block.contains($0.rect) }) {
                blocks.append((block, line.rect.height))
            }
        }
        return blocks
    }

    /// Whether `rect` is left-aligned with `reference`, like the lines of a block of text.
    private static func isInSameColumn(_ rect: CGRect, as reference: CGRect) -> Bool {
        abs(rect.minX - reference.minX) <= reference.height * 3
    }

    // MARK: - Merging

    /// Merges matches found more than once (by overlapping tiles, or by several recognition
    /// candidates of a line), keeping the union of their areas. Secret kinds win, so they get a
    /// solid fill.
    static func merged(_ matches: [SensitiveTextMatch]) -> [SensitiveTextMatch] {
        var result: [SensitiveTextMatch] = []
        var pending = matches.sorted { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }

        while !pending.isEmpty {
            var current = pending.removeFirst()
            var absorbed = true
            // A union can reach more matches, so repeat until nothing overlaps.
            while absorbed {
                absorbed = false
                pending.removeAll { other in
                    guard overlapRatio(current.rect, other.rect) >= 0.5 else { return false }
                    let kind = current.kind.needsSolidFill || !other.kind.needsSolidFill ? current.kind : other.kind
                    current = SensitiveTextMatch(kind: kind, rect: current.rect.union(other.rect))
                    absorbed = true
                    return true
                }
            }
            result.append(current)
        }
        return result.sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
    }

    /// Area shared by `a` and `b`, relative to the smaller one.
    private static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 ? intersection.width * intersection.height / smaller : 0
    }

    // MARK: - Geometry

    /// Converts a normalized Vision box (bottom-left origin) relative to `area` to a pixel
    /// rectangle of the whole image (top-left origin).
    static func pixelRect(fromNormalized box: CGRect, in area: CGRect) -> CGRect {
        CGRect(
            x: area.minX + box.minX * area.width,
            y: area.minY + (1 - box.maxY) * area.height,
            width: box.width * area.width,
            height: box.height * area.height
        )
    }

    /// `rect` with a margin around text of `lineHeight`, made integral and clamped to the image.
    static func padded(_ rect: CGRect, lineHeight: CGFloat, imageSize: CGSize) -> CGRect? {
        let padding = max(3, lineHeight * 0.2)
        let padded = rect.insetBy(dx: -padding, dy: -padding).integral
            .intersection(CGRect(origin: .zero, size: imageSize))
        guard !padded.isNull, padded.width >= 1, padded.height >= 1 else { return nil }
        return padded
    }
}

/// A text recognition request that can be cancelled from another thread.
private nonisolated final class RecognitionRequest: @unchecked Sendable {
    // Vision requests support `cancel()` while `perform` runs on another thread.
    let request: VNRecognizeTextRequest

    init() {
        request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
    }

    func cancel() {
        request.cancel()
    }
}
