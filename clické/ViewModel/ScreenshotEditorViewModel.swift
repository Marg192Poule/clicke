import SwiftUI
import AppKit
import AVFoundation
internal import Combine

// MARK: - Global Wallpaper Cache
/// Cache singleton pour éviter de recharger les wallpapers à chaque ouverture de l'éditeur
final class WallpaperCache {
    static let shared = WallpaperCache()
    
    private(set) var wallpapers: [(url: URL, image: NSImage)] = []
    private(set) var isLoaded = false
    private var isLoading = false
    private var loadCallbacks: [() -> Void] = []
    
    private init() {}
    
    /// Charge les wallpapers une seule fois, appelle le callback quand c'est prêt
    func loadIfNeeded(completion: @escaping ([(url: URL, image: NSImage)]) -> Void) {
        // Déjà chargé, retourner immédiatement
        if isLoaded {
            completion(wallpapers)
            return
        }
        
        // Chargement en cours, ajouter le callback à la liste
        if isLoading {
            loadCallbacks.append { [weak self] in
                completion(self?.wallpapers ?? [])
            }
            return
        }
        
        // Démarrer le chargement
        isLoading = true
        loadCallbacks.append { [weak self] in
            completion(self?.wallpapers ?? [])
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let loaded = self.loadAllWallpapers()
            
            DispatchQueue.main.async {
                self.wallpapers = loaded
                self.isLoaded = true
                self.isLoading = false
                
                // Appeler tous les callbacks en attente
                for callback in self.loadCallbacks {
                    callback()
                }
                self.loadCallbacks.removeAll()
            }
        }
    }
    
    /// Ajoute un wallpaper custom au début du cache
    func addCustomWallpaper(url: URL, image: NSImage) {
        // Éviter les doublons
        if !wallpapers.contains(where: { $0.url == url }) {
            wallpapers.insert((url, image), at: 0)
        }
    }
    
    /// Force le rechargement du cache
    func invalidate() {
        wallpapers.removeAll()
        isLoaded = false
    }
    
    // MARK: - Private Loading Logic
    private func loadAllWallpapers() -> [(url: URL, image: NSImage)] {
        var allFiles: [(url: URL, size: Int, isVideo: Bool, category: String)] = []
        let fm = FileManager.default
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "webp"]
        let videoExtensions = ["mov", "mp4"]
        
        // Get current desktop wallpaper via NSWorkspace
        var currentWallpaperURLs: [URL] = []
        for screen in NSScreen.screens {
            if let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen) {
                currentWallpaperURLs.append(wallpaperURL)
            }
        }
        
        // Add current wallpapers first
        for wallpaperURL in currentWallpaperURLs {
            if let attrs = try? fm.attributesOfItem(atPath: wallpaperURL.path),
               let size = attrs[.size] as? Int {
                let ext = wallpaperURL.pathExtension.lowercased()
                let isVideo = videoExtensions.contains(ext)
                allFiles.append((wallpaperURL, size, isVideo, "Current Wallpaper"))
            }
        }
        
        // All macOS wallpaper locations
        let homeDir = fm.homeDirectoryForCurrentUser.path
        let wallpaperPaths = [
            "\(homeDir)/Library/Application Support/com.apple.wallpaper/aerials/videos",
            "\(homeDir)/Library/Desktop Pictures",
            "\(homeDir)/Pictures",
            "/System/Library/Desktop Pictures",
            "/Library/Desktop Pictures",
            "/System/Library/ExtensionKit/Extensions/NeptuneOneWallpaper.appex/Contents/Resources",
            "/System/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture",
            "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS"
        ]
        
        for basePath in wallpaperPaths {
            guard fm.fileExists(atPath: basePath) else { continue }
            let baseURL = URL(fileURLWithPath: basePath)
            
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
                    if currentWallpaperURLs.contains(fileURL) { continue }
                    
                    if let attrs = try? fm.attributesOfItem(atPath: path),
                       let size = attrs[.size] as? Int {
                        let minSize = basePath.contains(homeDir) ? 50_000 : 100_000
                        if (isImage && size > minSize) || isVideo {
                            allFiles.append((fileURL, size, isVideo, ""))
                        }
                    }
                }
            }
        }
        
        // Remove duplicates
        var seen = Set<String>()
        allFiles = allFiles.filter { item in
            let name = item.url.lastPathComponent
            if seen.contains(name) { return false }
            seen.insert(name)
            return true
        }
        
        // Sort: videos first, then by size
        allFiles.sort {
            if $0.isVideo != $1.isVideo { return $0.isVideo }
            return $0.size > $1.size
        }
        
        // Load thumbnails
        var loaded: [(URL, NSImage)] = []
        for item in allFiles {
            var img: NSImage?
            
            if item.isVideo {
                img = extractFrameFromVideo(url: item.url)
            } else {
                img = loadImageFromFile(url: item.url)
            }
            
            if let image = img {
                let thumb = image.resizedProportionally(maxSize: NSSize(width: 400, height: 300))
                loaded.append((item.url, thumb ?? image))
            }
        }
        
        return loaded
    }
    
    private func loadImageFromFile(url: URL) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        
        if ext == "heic" || ext == "heif" {
            guard let ciImage = CIImage(contentsOf: url) else { return nil }
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        
        return NSImage(contentsOf: url)
    }
    
    private func extractFrameFromVideo(url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = CMTime.zero
        generator.requestedTimeToleranceBefore = CMTime.zero
        
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        
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
        
        // Try at 0 seconds
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
}

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
        
        // Charger l'image locale par défaut
        var defaultConfig = ScreenshotStyleConfig.default
        
        // Essayer plusieurs méthodes pour trouver l'image dans le bundle
        var imageURL: URL? = nil
        
        // Méthode 1: Avec subdirectory "public"
        if let url = Bundle.main.url(forResource: "Black and White Gradient Macbook Wallpaper_Texture", withExtension: "png", subdirectory: "public") {
            imageURL = url
        }
        // Méthode 2: Sans subdirectory (directement dans le bundle)
        else if let url = Bundle.main.url(forResource: "Black and White Gradient Macbook Wallpaper_Texture", withExtension: "png") {
            imageURL = url
        }
        // Méthode 3: Chemin relatif depuis le bundle
        else if let bundlePath = Bundle.main.resourcePath {
            let filePath = "\(bundlePath)/public/Black and White Gradient Macbook Wallpaper_Texture.png"
            if FileManager.default.fileExists(atPath: filePath) {
                imageURL = URL(fileURLWithPath: filePath)
            }
        }
        // Méthode 4: Chemin absolu (pour le développement)
        if imageURL == nil {
            let devPath = "/Users/nath/Desktop/clicke/clické/public/Black and White Gradient Macbook Wallpaper_Texture.png"
            if FileManager.default.fileExists(atPath: devPath) {
                imageURL = URL(fileURLWithPath: devPath)
            }
        }
        
        // Charger l'image si trouvée
        if let url = imageURL, let image = NSImage(contentsOf: url) {
            defaultConfig.backgroundImageURL = url
            defaultConfig.backgroundType = .image
            defaultConfig.selectedMagicPreset = nil
            defaultConfig.selectedGradient = nil
            defaultConfig.selectedSolidColor = nil
            self.selectedWallpaperURL = url
            
            // Précharger l'image dans la liste
            let thumb = image.resizedProportionally(maxSize: NSSize(width: 400, height: 300))
            self.wallpaperImages = [(url, thumb ?? image)]
        }
        
        self.config = defaultConfig
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
        // Utiliser le cache global pour éviter de recharger à chaque fois
        WallpaperCache.shared.loadIfNeeded { [weak self] cachedWallpapers in
            guard let self = self else { return }
            
            // Ajouter les wallpapers du cache sans écraser ceux déjà présents
            let existingURLs = Set(self.wallpaperImages.map { $0.url })
            let newWallpapers = cachedWallpapers.filter { !existingURLs.contains($0.url) }
            self.wallpaperImages.append(contentsOf: newWallpapers)
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
                let thumb = image.resizedProportionally(maxSize: NSSize(width: 400, height: 300)) ?? image
                
                // Add to beginning of list
                self.wallpaperImages.insert((url, thumb), at: 0)
                
                // Aussi ajouter au cache global pour les futures sessions
                WallpaperCache.shared.addCustomWallpaper(url: url, image: thumb)
                
                // Select it
                self.selectedWallpaperURL = url
                self.config.backgroundImageURL = url
                self.config.selectedMagicPreset = nil
                self.config.selectedGradient = nil
                self.config.selectedSolidColor = nil
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
    
    // MARK: - Zoom Actions
    func zoomIn() {
        let newZoom = min(config.zoom * 1.2, 300)
        config.zoom = newZoom
    }
    
    func zoomOut() {
        let newZoom = max(config.zoom / 1.2, 10)
        config.zoom = newZoom
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
    
    // MARK: - Gradient Actions
    func randomizeGradient() {
        // Generate harmonious colors
        let baseHue = Double.random(in: 0...1)
        
        // Color 1 - vibrant start
        config.gradientConfig.color1 = Color(
            hue: baseHue,
            saturation: Double.random(in: 0.6...1.0),
            brightness: Double.random(in: 0.7...0.95)
        )
        
        // Color 2 - middle tone (analogous)
        let hue2 = (baseHue + Double.random(in: 0.08...0.2)).truncatingRemainder(dividingBy: 1.0)
        config.gradientConfig.color2 = Color(
            hue: hue2,
            saturation: Double.random(in: 0.5...0.9),
            brightness: Double.random(in: 0.6...0.9)
        )
        
        // Color 3 - end (complementary or split)
        let hue3 = (baseHue + Double.random(in: 0.25...0.5)).truncatingRemainder(dividingBy: 1.0)
        config.gradientConfig.color3 = Color(
            hue: hue3,
            saturation: Double.random(in: 0.5...0.95),
            brightness: Double.random(in: 0.65...0.95)
        )
        
        // Randomize angle
        config.gradientConfig.angle = Double(Int.random(in: 0...7) * 45)
        
        // Clear preset selection
        config.selectedGradientPreset = nil
    }
}
