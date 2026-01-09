import SwiftUI
import AppKit
import AVFoundation
internal import Combine

// MARK: - Optimized Wallpaper Cache using NSCache
/// Cache singleton utilisant NSCache pour la gestion automatique de la mémoire
final class WallpaperCache {
    static let shared = WallpaperCache()
    
    // NSCache avec limite de mémoire automatique
    private let thumbnailCache = NSCache<NSURL, NSImage>()
    private var wallpaperURLs: [URL] = []
    private(set) var isLoaded = false
    private var isLoading = false
    private var loadCallbacks: [() -> Void] = []
    
    private init() {
        // Configurer les limites du cache (haute qualité)
        thumbnailCache.countLimit = 50 // Max 50 images en cache
        thumbnailCache.totalCostLimit = 150 * 1024 * 1024 // Max 150 MB pour images HD
    }
    
    /// Charge les wallpapers et retourne les URLs avec leurs thumbnails
    func loadIfNeeded(completion: @escaping ([(url: URL, image: NSImage)]) -> Void) {
        if isLoaded {
            completion(getCachedWallpapers())
            return
        }
        
        if isLoading {
            loadCallbacks.append { [weak self] in
                completion(self?.getCachedWallpapers() ?? [])
            }
            return
        }
        
        isLoading = true
        loadCallbacks.append { [weak self] in
            completion(self?.getCachedWallpapers() ?? [])
        }
        
        Task {
            await loadAllWallpapers()
            
            await MainActor.run {
                self.isLoaded = true
                self.isLoading = false
                
                for callback in self.loadCallbacks {
                    callback()
                }
                self.loadCallbacks.removeAll()
            }
        }
    }
    
    /// Récupère les wallpapers cachés
    func getCachedWallpapers() -> [(url: URL, image: NSImage)] {
        wallpaperURLs.compactMap { url in
            guard let image = thumbnailCache.object(forKey: url as NSURL) else { return nil }
            return (url, image)
        }
    }
    
    /// Ajoute un wallpaper custom au cache
    func addCustomWallpaper(url: URL, image: NSImage) {
        guard !wallpaperURLs.contains(url) else { return }
        
        wallpaperURLs.insert(url, at: 0)
        let cost = Int(image.size.width * image.size.height * 4) // Estimation en bytes
        thumbnailCache.setObject(image, forKey: url as NSURL, cost: cost)
    }
    
    /// Invalide le cache et force un rechargement
    func invalidate() {
        thumbnailCache.removeAllObjects()
        wallpaperURLs.removeAll()
        isLoaded = false
        isLoading = false
        loadCallbacks.removeAll()
    }
    
    /// Force le rechargement même si déjà chargé
    func forceReload(completion: @escaping ([(url: URL, image: NSImage)]) -> Void) {
        invalidate()
        loadIfNeeded(completion: completion)
    }
    
    // MARK: - Private Loading Logic
    private func loadAllWallpapers() async {
        var loadedURLs = Set<URL>()
        
        // Charger les wallpapers depuis le bundle (dossier public)
        if let resourcePath = Bundle.main.resourcePath {
            let possiblePaths = [
                (resourcePath as NSString).appendingPathComponent("public"),
                resourcePath
            ]
            
            for path in possiblePaths {
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: path) {
                    let imageFiles = contents.filter { 
                        $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") || $0.hasSuffix(".png") 
                    }
                    if !imageFiles.isEmpty {
                        let baseURL = URL(fileURLWithPath: path)
                        for file in imageFiles {
                            let fileURL = baseURL.appendingPathComponent(file)
                            await loadAndCache(url: fileURL, loadedURLs: &loadedURLs)
                        }
                        break
                    }
                }
            }
        }
    }
    
    /// Charge et met en cache une image (haute qualité pour les previews)
    private func loadAndCache(url: URL, loadedURLs: inout Set<URL>) async {
        // Charger en haute résolution pour une bonne qualité d'affichage
        if let image = await ImageLoadingService.shared.loadImage(from: url, maxDimension: 1200) {
            await MainActor.run {
                self.wallpaperURLs.append(url)
                let cost = Int(image.size.width * image.size.height * 4)
                self.thumbnailCache.setObject(image, forKey: url as NSURL, cost: cost)
            }
            loadedURLs.insert(url)
        }
    }
}

// MARK: - ScreenshotEditorViewModel
/// ViewModel optimisé avec debouncing et cache d'image partagée
@MainActor
class ScreenshotEditorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var config: ScreenshotStyleConfig = .default {
        didSet {
            // Invalider le cache de rendu quand la config change
            if config.renderHash != oldValue.renderHash {
                invalidateRenderCache()
            }
        }
    }
    @Published var wallpaperImages: [(url: URL, image: NSImage)] = []
    @Published var canvasSize: CGSize = .zero
    @Published var offset: CGSize = .zero
    @Published var lastOffset: CGSize = .zero
    @Published var selectedWallpaperURL: URL? = nil
    
    // Text overlay input
    @Published var newTextContent: String = ""
    @Published var newTextFontSize: CGFloat = 24
    @Published var newTextColor: Color = .white
    
    // Redact mode
    @Published var currentRedactStart: CGPoint? = nil
    @Published var currentRedactEnd: CGPoint? = nil
    
    // MARK: - Properties
    let originalImage: NSImage
    private let toastManager: ToastManager?
    
    // MARK: - Render Cache
    private var cachedRenderedImage: NSImage? = nil
    private var cachedRenderHash: Int = 0
    
    // MARK: - Cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(originalImage: NSImage, toastManager: ToastManager? = nil) {
        self.originalImage = originalImage
        self.toastManager = toastManager
        
        var defaultConfig = ScreenshotStyleConfig.default
        
        // Charger l'image par défaut depuis le bundle uniquement
        if let url = Bundle.main.url(forResource: "Black and White Gradient Macbook Wallpaper_Texture", withExtension: "png", subdirectory: "public") ??
           Bundle.main.url(forResource: "Black and White Gradient Macbook Wallpaper_Texture", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            defaultConfig.backgroundImageURL = url
            defaultConfig.backgroundType = .image
            defaultConfig.selectedMagicPreset = nil
            defaultConfig.selectedGradient = nil
            defaultConfig.selectedSolidColor = nil
            self.selectedWallpaperURL = url
            
            let thumb = image.resizedProportionally(maxSize: NSSize(width: 400, height: 300))
            self.wallpaperImages = [(url, thumb ?? image)]
        }
        
        self.config = defaultConfig
        
        // Setup debounced config updates
        setupConfigDebouncing()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Debouncing Setup
    private func setupConfigDebouncing() {
        // Debounce zoom changes for smooth preview
        $config
            .map { $0.zoom }
            .removeDuplicates()
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main) // ~60fps
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Render Cache Management
    private func invalidateRenderCache() {
        cachedRenderedImage = nil
    }
    
    /// Retourne l'image rendue, utilisant le cache si disponible
    private func getRenderedImage() -> NSImage? {
        let currentHash = config.renderHash
        
        // Utiliser le cache si valide
        if cachedRenderHash == currentHash, let cached = cachedRenderedImage {
            return cached
        }
        
        // Rendre et cacher
        let renderer = ScreenshotRenderer(image: originalImage, config: config)
        let rendered = renderer.render()
        
        cachedRenderedImage = rendered
        cachedRenderHash = currentHash
        
        return rendered
    }
    
    // MARK: - Calculate Fit Zoom
    func calculateFitZoom() {
        // Ne pas utiliser asyncAfter - calculer directement si canvasSize est disponible
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        
        let leftSidebarWidth: CGFloat = 320 + 24
        let availableWidth = max(canvasSize.width - leftSidebarWidth - 40, 200)
        let availableHeight = max(canvasSize.height - 60, 200)
        
        let totalWidth = originalImage.size.width + config.padding * 2
        let totalHeight = originalImage.size.height + config.padding * 2
        
        let fitScale = min(availableWidth / totalWidth, availableHeight / totalHeight, 1.0)
        
        withAnimation(.easeOut(duration: 0.25)) {
            config.zoom = fitScale * 100
            offset = .zero
            lastOffset = .zero
        }
    }
    
    func fitAndCenter() {
        calculateFitZoom()
    }
    
    // MARK: - Load Wallpapers
    func loadWallpapers() {
        WallpaperCache.shared.loadIfNeeded { [weak self] cachedWallpapers in
            guard let self = self else { return }
            
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
            Task {
                if let image = await ImageLoadingService.shared.loadImage(from: url, maxDimension: 400) {
                    await MainActor.run {
                        let thumb = ImageLoadingService.shared.createThumbnail(from: image)
                        
                        self.wallpaperImages.insert((url, thumb), at: 0)
                        WallpaperCache.shared.addCustomWallpaper(url: url, image: thumb)
                        
                        self.selectedWallpaperURL = url
                        self.config.backgroundImageURL = url
                        self.config.selectedMagicPreset = nil
                        self.config.selectedGradient = nil
                        self.config.selectedSolidColor = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Copy Action
    func copyAction() -> NSImage? {
        return getRenderedImage()
    }
    
    // MARK: - Save Action
    func saveAction() {
        guard let img = getRenderedImage() else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
        
        if panel.runModal() == .OK, let url = panel.url {
            try? img.saveAsPNG(to: url)
            toastManager?.show(message: "Saved", icon: "checkmark.circle.fill", success: true)
        }
    }
    
    // MARK: - Share Action
    func shareAction() {
        guard let img = getRenderedImage() else { return }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshot_\(Int(Date().timeIntervalSince1970)).png")
        
        guard let tiffData = img.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else { return }
        
        do {
            try pngData.write(to: tempURL)
            
            let picker = NSSharingServicePicker(items: [tempURL])
            
            if let window = NSApp.keyWindow, let contentView = window.contentView {
                let rect = NSRect(x: contentView.bounds.maxX - 100, y: contentView.bounds.maxY - 50, width: 1, height: 1)
                picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
            }
        } catch {
            print("Error saving temp file for sharing: \(error)")
        }
    }
    
    // MARK: - Get Shareable Image (cached)
    func getShareableImage() -> Image {
        if let img = getRenderedImage() {
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
        
        let canvasCenterX = canvasSize.width / 2 + offset.width + lastOffset.width
        let canvasCenterY = canvasSize.height / 2 + offset.height + lastOffset.height
        
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
        
        let canvasCenterX = canvasSize.width / 2 + offset.width + lastOffset.width
        let canvasCenterY = canvasSize.height / 2 + offset.height + lastOffset.height
        
        let screenX = (imageRect.origin.x - totalImageWidth / 2) * zoom + canvasCenterX
        let screenY = (imageRect.origin.y - totalImageHeight / 2) * zoom + canvasCenterY
        let screenWidth = imageRect.width * zoom
        let screenHeight = imageRect.height * zoom
        
        return CGRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight)
    }
    
    // MARK: - Zoom Actions
    func zoomIn() {
        withAnimation(.easeOut(duration: 0.2)) {
            config.zoom = min(config.zoom * 1.2, 300)
        }
    }
    
    func zoomOut() {
        withAnimation(.easeOut(duration: 0.2)) {
            config.zoom = max(config.zoom / 1.2, 10)
        }
    }
    
    // MARK: - Reset Actions
    func resetPosition() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            offset = .zero
            lastOffset = .zero
            config.rotation = 0
        }
    }
    
    func resetScreenshotOffset() {
        config.screenshotOffset = .zero
    }
    
    // MARK: - Gradient Actions
    func randomizeGradient() {
        let baseHue = Double.random(in: 0...1)
        
        config.gradientConfig.color1 = Color(
            hue: baseHue,
            saturation: Double.random(in: 0.6...1.0),
            brightness: Double.random(in: 0.7...0.95)
        )
        
        let hue2 = (baseHue + Double.random(in: 0.08...0.2)).truncatingRemainder(dividingBy: 1.0)
        config.gradientConfig.color2 = Color(
            hue: hue2,
            saturation: Double.random(in: 0.5...0.9),
            brightness: Double.random(in: 0.6...0.9)
        )
        
        let hue3 = (baseHue + Double.random(in: 0.25...0.5)).truncatingRemainder(dividingBy: 1.0)
        config.gradientConfig.color3 = Color(
            hue: hue3,
            saturation: Double.random(in: 0.5...0.95),
            brightness: Double.random(in: 0.65...0.95)
        )
        
        config.gradientConfig.angle = Double(Int.random(in: 0...7) * 45)
        config.selectedGradientPreset = nil
    }
}

