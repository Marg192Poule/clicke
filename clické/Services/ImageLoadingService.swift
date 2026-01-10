import AppKit
import AVFoundation
import CoreImage

// Note: Uses NSImage+Extensions for resizedProportionally

// MARK: - ImageLoadingService
/// Centralized service for image loading and processing.
/// Replaces all code duplications in the project.
actor ImageLoadingService {
    
    // MARK: - Singleton
    static let shared = ImageLoadingService()
    
    // MARK: - Shared Resources (GPU-accelerated)
    /// Shared CIContext to avoid expensive re-creations
    private let ciContext: CIContext = {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
            .highQualityDownsample: true
        ])
    }()
    
    // MARK: - Image Loading
    
    /// Loads an image from a URL (supports HEIC, standard images and videos)
    /// - Parameters:
    ///   - url: File URL
    ///   - maxDimension: Maximum dimension for resizing (nil = original size, max 4096 recommended)
    /// - Returns: The loaded image or nil
    func loadImage(from url: URL, maxDimension: CGFloat? = nil) async -> NSImage? {
        let videoExtensions = ["mov", "mp4", "m4v"]
        let isVideo = videoExtensions.contains(url.pathExtension.lowercased())
        
        // For videos, extract a frame
        if isVideo {
            let image = await extractFrameFromVideo(url: url)
            if let maxDim = maxDimension, let img = image {
                return resizeImage(img, maxDimension: maxDim)
            }
            return image
        }
        
        // For images with max size, use optimized loading
        // This avoids loading the full image into memory (prevents IOSurface errors)
        // CGImageSource supports HEIC on macOS, so we can use the same approach
        if let maxDim = maxDimension {
            return loadImageWithMaxSize(from: url, maxPixelSize: maxDim)
        }
        
        // Without size limit, load normally
        return loadImageFromFile(url: url)
    }
    
    /// Loads an image from a file with optimized HEIC support
    func loadImageFromFile(url: URL) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        
        // For HEIC/HEIF files, use CIImage with shared context
        if ext == "heic" || ext == "heif" {
            return loadHEICImage(from: url)
        }
        
        // For other formats, use CGImageSource (more performant)
        return loadStandardImage(from: url)
    }
    
    // MARK: - Private Loading Methods
    
    private func loadHEICImage(from url: URL) -> NSImage? {
        guard let ciImage = CIImage(contentsOf: url) else { return nil }
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    private func loadStandardImage(from url: URL) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return NSImage(contentsOf: url)
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    /// Loads an image with maximum size (avoids IOSurface errors)
    private func loadImageWithMaxSize(from url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        
        // Use CGImageSource to directly create thumbnail at the right size
        // This avoids loading the full image into memory
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            // Fallback: load normally
            return loadStandardImage(from: url)
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    // MARK: - Video Frame Extraction
    
    /// Extracts a frame from a video asynchronously (non-blocking)
    func extractFrameFromVideo(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        generator.maximumSize = CGSize(width: 3840, height: 2160) // 4K max
        
        // Try first at 1 second
        if let image = await extractFrame(generator: generator, at: CMTime(seconds: 1, preferredTimescale: 600)) {
            return image
        }
        
        // Fallback to 0 seconds
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
    
    /// Resizes an image while preserving proportions
    func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage? {
        // Don't resize if already small enough
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
        
        // Use CGContext for GPU-accelerated resizing
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
    
    /// Fallback for resizing if GPU unavailable
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
/// Wrapper to allow synchronous calls from non-async contexts
extension ImageLoadingService {
    
    /// Loads an image synchronously (for compatibility with existing code)
    /// ⚠️ Prefer async version when possible
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
    
    /// Creates an optimized thumbnail (nonisolated for synchronous access)
    nonisolated func createThumbnail(from image: NSImage, maxSize: NSSize = NSSize(width: 400, height: 300)) -> NSImage {
        // Proportional resize calculation
        let aspectRatio = image.size.width / image.size.height
        var newSize: NSSize
        
        if aspectRatio > 1 {
            newSize = NSSize(width: maxSize.width, height: maxSize.width / aspectRatio)
        } else {
            newSize = NSSize(width: maxSize.height * aspectRatio, height: maxSize.height)
        }
        
        // Ensure we don't exceed limits
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
