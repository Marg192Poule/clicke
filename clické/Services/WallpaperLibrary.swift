import AppKit
import Observation

/// The wallpapers offered as backgrounds: the ones bundled with the app plus images the user imported.
///
/// Thumbnails are small (≈200 px) and decoded concurrently off the main actor, so the whole
/// grid costs a few MB instead of decoding every wallpaper at full size.
@Observable
final class WallpaperLibrary {
    static let shared = WallpaperLibrary()

    struct Entry: Identifiable, Hashable {
        let source: BackgroundImageSource
        let url: URL
        let name: String

        var id: BackgroundImageSource { source }
    }

    /// Longest side of the grid thumbnails, in pixels.
    static let thumbnailPixelSize = 200

    private(set) var entries: [Entry] = []
    private(set) var thumbnails: [BackgroundImageSource: CGImage] = [:]
    private(set) var isLoading = false
    private var didStartLoading = false

    private init() {}

    // MARK: Loading

    /// Discovers the bundled wallpapers and loads their thumbnails (once per app session).
    func loadIfNeeded() {
        guard !didStartLoading else { return }
        didStartLoading = true
        isLoading = true

        Task {
            let bundled = await Self.discoverBundledWallpapers()
            let known = Set(entries.map(\.source))
            entries.append(contentsOf: bundled.filter { !known.contains($0.source) })
            isLoading = false
            await loadThumbnails(for: bundled)
        }
    }

    /// Adds a user-picked image (shown first in the grid) and returns its source.
    @discardableResult
    func addImportedImage(at url: URL) -> BackgroundImageSource {
        let source = BackgroundImageSource.file(url)
        if !entries.contains(where: { $0.source == source }) {
            entries.insert(Entry(source: source, url: url, name: url.deletingPathExtension().lastPathComponent), at: 0)
            Task { await loadThumbnails(for: [entries[0]]) }
        }
        return source
    }

    /// Decodes thumbnails a few at a time, at utility priority, so they never compete with the
    /// editor's first frame or with the background the canvas is waiting for.
    private func loadThumbnails(for entries: [Entry]) async {
        let size = Self.thumbnailPixelSize
        var pending = entries.filter { thumbnails[$0.source] == nil }[...]
        let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)

        await withTaskGroup(of: (BackgroundImageSource, CGImage?).self) { group in
            func enqueueNext() {
                guard let entry = pending.popFirst() else { return }
                let url = entry.url
                let source = entry.source
                group.addTask(priority: .utility) {
                    (source, await ImageLoadingService.loadImage(at: url, maxPixelSize: size))
                }
            }
            for _ in 0..<maxConcurrent { enqueueNext() }
            for await (source, image) in group {
                if let image { thumbnails[source] = image }
                enqueueNext()
            }
        }
    }

    // MARK: Discovery

    /// Bundled images large enough to be wallpapers (other images that may be bundled, e.g. icons, are ignored).
    @concurrent
    private static func discoverBundledWallpapers() async -> [Entry] {
        guard let resources = Bundle.main.resourceURL else { return [] }
        var found: [Entry] = []
        var seen = Set<String>()

        for folder in [resources.appendingPathComponent("public"), resources] {
            guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for url in files where BackgroundImageSource.imageExtensions.contains(url.pathExtension.lowercased()) {
                let baseName = url.deletingPathExtension().lastPathComponent
                guard !seen.contains(baseName),
                      let size = ImageLoadingService.pixelSize(of: url),
                      min(size.width, size.height) >= 1000 else { continue }
                seen.insert(baseName)
                found.append(Entry(source: .bundled(baseName), url: url, name: displayName(forFileName: baseName)))
            }
        }

        let defaultSource = BackgroundImageSource.defaultWallpaper
        return found.sorted { lhs, rhs in
            if lhs.source == defaultSource { return true }
            if rhs.source == defaultSource { return false }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
    }

    /// Turns "macos-sonoma-6016x6016-11574" into "Macos Sonoma" for tooltips and VoiceOver.
    nonisolated static func displayName(forFileName name: String) -> String {
        let noise: Set<String> = ["stock", "wallpaper", "5k", "4k", "retina", "macbook"]
        let words = name
            .split(whereSeparator: { "-_ ".contains($0) })
            .map(String.init)
            .filter { word in
                let lower = word.lowercased()
                let isNumeric = lower.allSatisfy { $0.isNumber || $0 == "x" } && lower.contains(where: \.isNumber)
                return !isNumeric && !noise.contains(lower)
            }
        let result = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return result.isEmpty ? name : result
    }
}
