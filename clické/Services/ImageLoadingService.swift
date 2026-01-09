import AppKit
import AVFoundation
import CoreImage

// Note: Uses NSImage+Extensions for resizedProportionally

// MARK: - ImageLoadingService
/// Service centralisé pour le chargement et le traitement d'images
/// Remplace toutes les duplications de code dans le projet
actor ImageLoadingService {
    
    // MARK: - Singleton
    static let shared = ImageLoadingService()
    
    // MARK: - Shared Resources (GPU-accelerated)
    /// CIContext partagé pour éviter les recréations coûteuses
    private let ciContext: CIContext = {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
            .highQualityDownsample: true
        ])
    }()
    
    // MARK: - Image Loading
    
    /// Charge une image depuis une URL (supporte HEIC, images standard et vidéos)
    /// - Parameters:
    ///   - url: URL du fichier
    ///   - maxDimension: Dimension maximale pour le redimensionnement (nil = taille originale)
    /// - Returns: L'image chargée ou nil
    func loadImage(from url: URL, maxDimension: CGFloat? = nil) async -> NSImage? {
        let videoExtensions = ["mov", "mp4", "m4v"]
        let isVideo = videoExtensions.contains(url.pathExtension.lowercased())
        
        let image: NSImage?
        if isVideo {
            image = await extractFrameFromVideo(url: url)
        } else {
            image = loadImageFromFile(url: url)
        }
        
        // Redimensionner si nécessaire
        if let maxDim = maxDimension, let img = image {
            return resizeImage(img, maxDimension: maxDim)
        }
        
        return image
    }
    
    /// Charge une image depuis un fichier avec support HEIC optimisé
    func loadImageFromFile(url: URL) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        
        // Pour les fichiers HEIC/HEIF, utiliser CIImage avec le contexte partagé
        if ext == "heic" || ext == "heif" {
            return loadHEICImage(from: url)
        }
        
        // Pour les autres formats, utiliser CGImageSource (plus performant)
        return loadStandardImage(from: url)
    }
    
    // MARK: - Private Loading Methods
    
    private func loadHEICImage(from url: URL) -> NSImage? {
        guard let ciImage = CIImage(contentsOf: url) else { return nil }
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    private func loadStandardImage(from url: URL) -> NSImage? {
        // Options pour forcer le chargement en pleine résolution
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldAllowFloat: true
        ]
        
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        
        // Options pour l'extraction de l'image - forcer la pleine résolution
        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailFromImageAlways: false
        ]
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, imageOptions as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    // MARK: - Video Frame Extraction
    
    /// Extrait une frame d'une vidéo de manière asynchrone (sans bloquer)
    func extractFrameFromVideo(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        generator.maximumSize = CGSize(width: 3840, height: 2160) // 4K max
        
        // Essayer d'abord à 1 seconde
        if let image = await extractFrame(generator: generator, at: CMTime(seconds: 1, preferredTimescale: 600)) {
            return image
        }
        
        // Fallback à 0 seconde
        return await extractFrame(generator: generator, at: .zero)
    }
    
    private func extractFrame(generator: AVAssetImageGenerator, at time: CMTime) async -> NSImage? {
        await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                if let cgImage = cgImage {
                    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // MARK: - Image Resizing (GPU-accelerated)
    
    /// Redimensionne une image en conservant les proportions
    func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage? {
        // Ne pas redimensionner si déjà assez petit
        guard image.size.width > maxDimension || image.size.height > maxDimension else {
            return image
        }
        
        let aspectRatio = image.size.width / image.size.height
        let newSize: NSSize
        
        if aspectRatio > 1 {
            newSize = NSSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = NSSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        // Utiliser CGContext pour le redimensionnement GPU-acceleré
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmapRep.cgImage else {
            return resizeImageFallback(image, to: newSize)
        }
        
        guard let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return resizeImageFallback(image, to: newSize)
        }
        
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: newSize))
        
        guard let resizedCGImage = context.makeImage() else {
            return resizeImageFallback(image, to: newSize)
        }
        
        return NSImage(cgImage: resizedCGImage, size: newSize)
    }
    
    /// Fallback pour le redimensionnement si GPU non disponible
    private func resizeImageFallback(_ image: NSImage, to newSize: NSSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
}

// MARK: - Synchronous Wrapper for Compatibility
/// Wrapper pour permettre l'appel synchrone depuis les contextes non-async
extension ImageLoadingService {
    
    /// Charge une image de manière synchrone (pour la compatibilité avec le code existant)
    /// ⚠️ Préférer la version async quand possible
    nonisolated func loadImageSync(from url: URL, maxDimension: CGFloat? = nil) -> NSImage? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: NSImage?
        
        Task {
            result = await loadImage(from: url, maxDimension: maxDimension)
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
    
    /// Crée une miniature optimisée (nonisolated pour accès synchrone)
    nonisolated func createThumbnail(from image: NSImage, maxSize: NSSize = NSSize(width: 400, height: 300)) -> NSImage {
        // Calcul proportionnel du redimensionnement
        let aspectRatio = image.size.width / image.size.height
        var newSize: NSSize
        
        if aspectRatio > 1 {
            newSize = NSSize(width: maxSize.width, height: maxSize.width / aspectRatio)
        } else {
            newSize = NSSize(width: maxSize.height * aspectRatio, height: maxSize.height)
        }
        
        // S'assurer de ne pas dépasser les limites
        if newSize.width > maxSize.width {
            newSize.width = maxSize.width
            newSize.height = maxSize.width / aspectRatio
        }
        if newSize.height > maxSize.height {
            newSize.height = maxSize.height
            newSize.width = maxSize.height * aspectRatio
        }
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
