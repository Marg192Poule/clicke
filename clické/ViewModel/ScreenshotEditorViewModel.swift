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
            let fm = FileManager.default
            let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "webp"]
            let videoExtensions = ["mov", "mp4"]
            
            // APPROACH 1: Get current desktop wallpaper via NSWorkspace (most reliable)
            var currentWallpaperURLs: [URL] = []
            for screen in NSScreen.screens {
                if let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen) {
                    currentWallpaperURLs.append(wallpaperURL)
                }
            }
            
            // Add current wallpapers first (priority)
            for wallpaperURL in currentWallpaperURLs {
                if let attrs = try? fm.attributesOfItem(atPath: wallpaperURL.path),
                   let size = attrs[.size] as? Int {
                    let ext = wallpaperURL.pathExtension.lowercased()
                    let isVideo = videoExtensions.contains(ext)
                    allFiles.append((wallpaperURL, size, isVideo, "Current Wallpaper"))
                }
            }
            
            // APPROACH 2: All macOS wallpaper locations (system + user)
            let homeDir = fm.homeDirectoryForCurrentUser.path
            let wallpaperPaths = [
                // User's downloaded aerial wallpapers (Tahoe 26 dynamic wallpapers cache)
                "\(homeDir)/Library/Application Support/com.apple.wallpaper/aerials/videos",
                // User's personal wallpapers
                "\(homeDir)/Library/Desktop Pictures",
                "\(homeDir)/Pictures",
                // System wallpapers
                "/System/Library/Desktop Pictures",
                "/Library/Desktop Pictures",
                // macOS Tahoe 26 wallpapers (NeptuneOneWallpaper extension)
                "/System/Library/ExtensionKit/Extensions/NeptuneOneWallpaper.appex/Contents/Resources",
                // Dynamic wallpapers assets
                "/System/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture",
                "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS"
            ]
            
            for basePath in wallpaperPaths {
                guard fm.fileExists(atPath: basePath) else { continue }
                let baseURL = URL(fileURLWithPath: basePath)
                
                // Determine category from base path
                let baseCategory: String
                if basePath.contains(homeDir) {
                    baseCategory = "My Pictures"
                } else {
                    baseCategory = "System"
                }
                
                // Enumerate including hidden directories
                if let enumerator = fm.enumerator(
                    at: baseURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
                    options: []
                ) {
                    for case let fileURL as URL in enumerator {
                        let path = fileURL.path
                        let ext = fileURL.pathExtension.lowercased()
                        
                        // Skip thumbnails, low-quality, and system files
                        if path.contains("/.thumbnails/") { continue }
                        if path.contains("Thumbnail") { continue }
                        if path.contains("/Solid Colors/") { continue }
                        if path.contains("@2x") { continue }
                        if path.contains("Portrait") { continue }
                        if path.contains(".DS_Store") { continue }
                        if path.contains("Photo Booth") { continue }
                        if path.contains("Screenshots") { continue }
                        
                        let isImage = imageExtensions.contains(ext)
                        let isVideo = videoExtensions.contains(ext)
                        
                        guard isImage || isVideo else { continue }
                        
                        // Skip if already added as current wallpaper
                        if currentWallpaperURLs.contains(fileURL) { continue }
                        
                        // Determine subcategory from path
                        var category = baseCategory
                        if path.contains("Tahoe") || path.contains("tahoe") || path.contains("Neptune") { category = "Tahoe" }
                        else if path.contains("Sequoia") || path.contains("sequoia") { category = "Sequoia" }
                        else if path.contains("Sonoma") || path.contains("sonoma") { category = "Sonoma" }
                        else if path.contains("Ventura") || path.contains("ventura") { category = "Ventura" }
                        else if path.contains("Monterey") || path.contains("monterey") { category = "Monterey" }
                        else if path.contains("Big Sur") || path.contains("bigsur") { category = "Big Sur" }
                        else if path.contains("Catalina") || path.contains("catalina") { category = "Catalina" }
                        else if path.contains("Mojave") || path.contains("mojave") { category = "Mojave" }
                        
                        // Get file size - quality filter
                        if let attrs = try? fm.attributesOfItem(atPath: path),
                           let size = attrs[.size] as? Int {
                            // User images: > 50KB, System: > 100KB
                            let minSize = basePath.contains(homeDir) ? 50_000 : 100_000
                            if (isImage && size > minSize) || isVideo {
                                allFiles.append((fileURL, size, isVideo, category))
                            }
                        }
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
            
            // Load all items (no limit)
            var loaded: [(URL, NSImage)] = []
            for item in allFiles {
                var img: NSImage?
                
                if item.isVideo {
                    // Extract frame from video
                    img = self.extractFrameFromVideo(url: item.url)
                } else {
                    // Load image, convert HEIC to standard format if needed
                    img = self.loadImageFromFile(url: item.url)
                }
                
                if let image = img {
                    // Create higher quality thumbnail for display
                    let thumb = image.resizedProportionally(maxSize: NSSize(width: 400, height: 300))
                    loaded.append((item.url, thumb ?? image))
                }
            }
            
            DispatchQueue.main.async {
                self.wallpaperImages = loaded
            }
        }
    }
    
    // MARK: - Import Custom Image
    func importCustomImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .jpeg, .png, .heic, .tiff]
        panel.message = "Select an image for background"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let image = loadImageFromFile(url: url) {
                let thumb = image.resizedProportionally(maxSize: NSSize(width: 400, height: 300))
                
                DispatchQueue.main.async {
                    // Add to beginning of list
                    self.wallpaperImages.insert((url, thumb ?? image), at: 0)
                    // Select it
                    self.selectedWallpaperURL = url
                    self.config.backgroundImageURL = url
                    self.config.selectedMagicPreset = nil
                    self.config.selectedGradient = nil
                    self.config.selectedSolidColor = nil
                }
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
    
    // MARK: - Share Action
    func shareAction() {
        guard let img = ScreenshotRenderer(image: originalImage, config: config).render() else { return }
        
        // Créer un fichier temporaire pour partager
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot_\(Int(Date().timeIntervalSince1970)).png")
        
        // Sauvegarder l'image dans le fichier temporaire
        guard let tiffData = img.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else { return }
        
        do {
            try pngData.write(to: tempURL)
            
            // Créer et afficher le NSSharingServicePicker
            DispatchQueue.main.async {
                let picker = NSSharingServicePicker(items: [tempURL])
                
                // Trouver la fenêtre active pour positionner le picker
                if let window = NSApp.keyWindow,
                   let contentView = window.contentView {
                    // Position du bouton share dans la toolbar (en haut à droite)
                    let rect = NSRect(x: contentView.bounds.maxX - 100, y: contentView.bounds.maxY - 50, width: 1, height: 1)
                    picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
                }
            }
        } catch {
            print("Error saving temp file for sharing: \(error)")
        }
    }
    
    // MARK: - Get Shareable Image
    func getShareableImage() -> Image {
        if let img = ScreenshotRenderer(image: originalImage, config: config).render() {
            return Image(nsImage: img)
        }
        return Image(nsImage: originalImage)
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
    
    // MARK: - Mesh Gradient Actions
    func randomizeMeshGradient() {
        // Generate 4 harmonious colors with good contrast
        let baseHue = Double.random(in: 0...1)
        
        // Accent color 1 - vibrant primary
        config.meshGradientConfig.color1 = Color(
            hue: baseHue,
            saturation: Double.random(in: 0.7...1.0),
            brightness: Double.random(in: 0.7...0.95)
        )
        
        // Accent color 2 - complementary or split
        let hue2 = (baseHue + Double.random(in: 0.3...0.5)).truncatingRemainder(dividingBy: 1.0)
        config.meshGradientConfig.color2 = Color(
            hue: hue2,
            saturation: Double.random(in: 0.6...0.95),
            brightness: Double.random(in: 0.65...0.9)
        )
        
        // Deep background - dark version of base
        config.meshGradientConfig.color3 = Color(
            hue: baseHue,
            saturation: Double.random(in: 0.4...0.7),
            brightness: Double.random(in: 0.05...0.15)
        )
        
        // Mid-tone - bridge between accent and dark
        let hue4 = (baseHue + Double.random(in: 0.1...0.25)).truncatingRemainder(dividingBy: 1.0)
        config.meshGradientConfig.color4 = Color(
            hue: hue4,
            saturation: Double.random(in: 0.5...0.8),
            brightness: Double.random(in: 0.4...0.7)
        )
        
        // Randomize blur slightly
        config.meshGradientConfig.blurAmount = Double.random(in: 40...80)
    }
}
