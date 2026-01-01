import SwiftUI
import AppKit
import AVFoundation
internal import Combine

/// ViewModel pour l'éditeur de screenshots - contient toute la logique métier
class ScreenshotEditorViewModel: ObservableObject {
    // MARK: - Published Properties (État observable)
    @Published var config: ScreenshotStyleConfig = .default
    @Published var wallpaperImages: [(url: URL, image: NSImage)] = []
    @Published var canvasSize: CGSize = .zero
    @Published var offset: CGSize = .zero
    @Published var lastOffset: CGSize = .zero
    @Published var selectedWallpaperURL: URL? = nil
    
    // Text overlay input
    @Published var newTextContent: String = ""
    @Published var newTextFontSize: CGFloat = 24
    @Published var newTextColor: Color = .white
    
    // Redact mode drawing
    @Published var currentRedactStart: CGPoint? = nil
    @Published var currentRedactEnd: CGPoint? = nil
    
    // MARK: - Properties
    let originalImage: NSImage
    private let toastManager: ToastManager?
    
    // MARK: - Initialization
    init(originalImage: NSImage, toastManager: ToastManager? = nil) {
        self.originalImage = originalImage
        self.toastManager = toastManager
        self.config = .default
    }
    
    // MARK: - Calculate Fit Zoom
    func calculateFitZoom() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            // Account for sidebar: left (320 + 12 padding on each side)
            let leftSidebarWidth: CGFloat = 320 + 24
            let availableWidth = max(self.canvasSize.width - leftSidebarWidth - 40, 200)
            let availableHeight = max(self.canvasSize.height - 60, 200)
            
            let totalWidth = self.originalImage.size.width + self.config.padding * 2
            let totalHeight = self.originalImage.size.height + self.config.padding * 2
            
            let fitScale = min(availableWidth / totalWidth, availableHeight / totalHeight, 1.0)
            self.config.zoom = fitScale * 100
            
            // Center the image in the available space
            self.offset = .zero
            self.lastOffset = .zero
        }
    }
    
    func fitAndCenter() {
        calculateFitZoom()
    }
    
    // MARK: - Load Wallpapers
    func loadWallpapers() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var allFiles: [(url: URL, size: Int, isVideo: Bool, category: String)] = []
            
            // All macOS wallpaper locations
            let wallpaperPaths = [
                "/System/Library/Desktop Pictures",
                "/Library/Desktop Pictures",
                NSHomeDirectory() + "/Library/Desktop Pictures",
                // Sonoma+ dynamic wallpapers
                "/System/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture"
            ]
            
            let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "webp"]
            let videoExtensions = ["mov", "mp4"]
            
            let fm = FileManager.default
            
            for basePath in wallpaperPaths {
                guard fm.fileExists(atPath: basePath) else { continue }
                let baseURL = URL(fileURLWithPath: basePath)
                
                // Enumerate including hidden directories like .wallpapers
                if let enumerator = fm.enumerator(
                    at: baseURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
                    options: [] // No options = include hidden files
                ) {
                    for case let fileURL as URL in enumerator {
                        let path = fileURL.path
                        let ext = fileURL.pathExtension.lowercased()
                        
                        // Skip thumbnails and low-quality folders
                        if path.contains("/.thumbnails/") { continue }
                        if path.contains("Thumbnail") { continue }
                        if path.contains("/Solid Colors/") { continue }
                        if path.contains("@2x") && !path.contains("@3x") { continue } // Prefer highest res
                        
                        let isImage = imageExtensions.contains(ext)
                        let isVideo = videoExtensions.contains(ext)
                        
                        guard isImage || isVideo else { continue }
                        
                        // Determine category from path
                        var category = "Other"
                        if path.contains("Ventura") || path.contains("ventura") { category = "Ventura" }
                        else if path.contains("Sonoma") || path.contains("sonoma") { category = "Sonoma" }
                        else if path.contains("Sequoia") || path.contains("sequoia") { category = "Sequoia" }
                        else if path.contains("Monterey") || path.contains("monterey") { category = "Monterey" }
                        else if path.contains("Big Sur") || path.contains("bigsur") { category = "Big Sur" }
                        else if path.contains("Catalina") || path.contains("catalina") { category = "Catalina" }
                        else if path.contains("Mojave") || path.contains("mojave") { category = "Mojave" }
                        else if path.contains("Abstract") || path.contains("abstract") { category = "Abstract" }
                        else if path.contains("Nature") || path.contains("nature") { category = "Nature" }
                        else if path.contains("Landscape") || path.contains("landscape") { category = "Landscape" }
                        
                        // Get file size to prioritize high-res images
                        if let attrs = try? fm.attributesOfItem(atPath: path),
                           let size = attrs[.size] as? Int {
                            // Images > 50KB or any video (dynamic wallpapers)
                            if (isImage && size > 50_000) || isVideo {
                                allFiles.append((fileURL, size, isVideo, category))
                            }
                        }
                    }
                }
            }
            
            // Also try to get user's current wallpaper
            if let screen = NSScreen.main,
               let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen) {
                if !allFiles.contains(where: { $0.url == wallpaperURL }) {
                    if let attrs = try? fm.attributesOfItem(atPath: wallpaperURL.path),
                       let size = attrs[.size] as? Int {
                        let ext = wallpaperURL.pathExtension.lowercased()
                        let isVideo = videoExtensions.contains(ext)
                        allFiles.insert((wallpaperURL, size, isVideo, "Current"), at: 0)
                    }
                }
            }
            
            // Remove duplicates based on filename
            var seen = Set<String>()
            allFiles = allFiles.filter { item in
                let name = item.url.lastPathComponent
                if seen.contains(name) { return false }
                seen.insert(name)
                return true
            }
            
            // Sort: videos first (dynamic wallpapers), then by size (highest quality first)
            allFiles.sort {
                if $0.isVideo != $1.isVideo { return $0.isVideo }
                return $0.size > $1.size
            }
            
            // Load top 50 items for more variety
            var loaded: [(URL, NSImage)] = []
            for item in allFiles.prefix(50) {
                var img: NSImage?
                
                if item.isVideo {
                    // Extract frame from video
                    img = self.extractFrameFromVideo(url: item.url)
                } else {
                    // Load image, convert HEIC to standard format if needed
                    img = self.loadImageFromFile(url: item.url)
                }
                
                if let image = img {
                    // Create smaller thumbnail for faster loading
                    let thumb = image.resizedProportionally(maxSize: NSSize(width: 200, height: 150))
                    loaded.append((item.url, thumb ?? image))
                }
            }
            
            DispatchQueue.main.async {
                self.wallpaperImages = loaded
            }
        }
    }
    
    // Load image from file, handling HEIC conversion
    private func loadImageFromFile(url: URL) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        
        // For HEIC files, use CIImage for better compatibility
        if ext == "heic" || ext == "heif" {
            guard let ciImage = CIImage(contentsOf: url) else { return nil }
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        
        // Standard image loading for other formats
        return NSImage(contentsOf: url)
    }
    
    // Extract first frame from video file
    private func extractFrameFromVideo(url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = CMTime.zero
        generator.requestedTimeToleranceBefore = CMTime.zero
        
        // Get frame at 1 second (or 0 if video is shorter)
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        
        // Use the new async API with semaphore to maintain synchronous behavior
        let semaphore = DispatchSemaphore(value: 0)
        var resultImage: NSImage? = nil
        
        generator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
            if let cgImage = cgImage {
                resultImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let image = resultImage {
            return image
        }
        
        // Try at 0 seconds if first attempt failed
        let semaphore2 = DispatchSemaphore(value: 0)
        resultImage = nil
        
        generator.generateCGImageAsynchronously(for: .zero) { cgImage, actualTime, error in
            if let cgImage = cgImage {
                resultImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            semaphore2.signal()
        }
        
        semaphore2.wait()
        return resultImage
    }
    
    // MARK: - Copy Action
    func copyAction() -> NSImage? {
        return ScreenshotRenderer(image: originalImage, config: config).render()
    }
    
    // MARK: - Save Action
    func saveAction() {
        guard let img = ScreenshotRenderer(image: originalImage, config: config).render() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
        if panel.runModal() == .OK, let url = panel.url {
            try? img.saveAsPNG(to: url)
            toastManager?.show(
                message: "Saved",
                icon: "checkmark.circle.fill",
                success: true
            )
        }
    }
    
    // MARK: - Text Overlay Actions
    func addTextOverlay() {
        guard !newTextContent.isEmpty else { return }
        let newOverlay = TextOverlay(
            text: newTextContent,
            fontSize: newTextFontSize,
            color: newTextColor
        )
        config.textOverlays.append(newOverlay)
        newTextContent = ""
    }
    
    func removeTextOverlay(_ id: UUID) {
        config.textOverlays.removeAll { $0.id == id }
    }
    
    func toggleTextBlur(_ id: UUID) {
        if let index = config.textOverlays.firstIndex(where: { $0.id == id }) {
            config.textOverlays[index].isBlurred.toggle()
        }
    }
    
    // MARK: - Redact Region Actions
    func addRedactRegion(_ region: RedactRegion) {
        config.redactRegions.append(region)
    }
    
    func removeRedactRegion(_ id: UUID) {
        config.redactRegions.removeAll { $0.id == id }
    }
    
    func clearAllRedactRegions() {
        config.redactRegions.removeAll()
    }
    
    // MARK: - Coordinate Conversion
    func screenToImageCoordinates(_ screenRect: CGRect) -> CGRect {
        let zoom = config.zoom / 100
        let totalImageWidth = originalImage.size.width + config.padding * 2
        let totalImageHeight = originalImage.size.height + config.padding * 2
        
        // Center of canvas
        let canvasCenterX = canvasSize.width / 2 + offset.width + lastOffset.width
        let canvasCenterY = canvasSize.height / 2 + offset.height + lastOffset.height
        
        // Convert screen rect to image-relative rect
        let relativeX = (screenRect.origin.x - canvasCenterX) / zoom + totalImageWidth / 2
        let relativeY = (screenRect.origin.y - canvasCenterY) / zoom + totalImageHeight / 2
        let relativeWidth = screenRect.width / zoom
        let relativeHeight = screenRect.height / zoom
        
        return CGRect(x: relativeX, y: relativeY, width: relativeWidth, height: relativeHeight)
    }
    
    func imageToScreenCoordinates(_ imageRect: CGRect) -> CGRect {
        let zoom = config.zoom / 100
        let totalImageWidth = originalImage.size.width + config.padding * 2
        let totalImageHeight = originalImage.size.height + config.padding * 2
        
        // Center of canvas
        let canvasCenterX = canvasSize.width / 2 + offset.width + lastOffset.width
        let canvasCenterY = canvasSize.height / 2 + offset.height + lastOffset.height
        
        // Convert image-relative rect to screen rect
        let screenX = (imageRect.origin.x - totalImageWidth / 2) * zoom + canvasCenterX
        let screenY = (imageRect.origin.y - totalImageHeight / 2) * zoom + canvasCenterY
        let screenWidth = imageRect.width * zoom
        let screenHeight = imageRect.height * zoom
        
        return CGRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight)
    }
    
    // MARK: - Reset Actions
    func resetPosition() {
        offset = .zero
        lastOffset = .zero
        config.rotation = 0
    }
    
    func resetScreenshotOffset() {
        config.screenshotOffset = .zero
    }
}

