import AppKit

extension NSImage {
    func saveAsPNG(to url: URL) throws {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ImageError", code: 1, userInfo: nil)
        }

        try pngData.write(to: url)
    }

    func toPNGData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmapImage.representation(using: .png, properties: [:])
    }
    
    func resized(to newSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    func resizedProportionally(maxSize: NSSize) -> NSImage? {
        let aspectRatio = self.size.width / self.size.height
        var newSize: NSSize
        
        if aspectRatio > 1 {
            // Landscape
            newSize = NSSize(width: maxSize.width, height: maxSize.width / aspectRatio)
        } else {
            // Portrait
            newSize = NSSize(width: maxSize.height * aspectRatio, height: maxSize.height)
        }
        
        // Ensure we don't exceed max dimensions
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
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    /// Optimized resize for preview - keeps max dimension under specified limit for smooth animations
    /// Uses GPU-accelerated Core Image for best performance
    func resizedForPreview(maxDimension: CGFloat) -> NSImage? {
        // Skip if already small enough
        guard self.size.width > maxDimension || self.size.height > maxDimension else {
            return self
        }
        
        let aspectRatio = self.size.width / self.size.height
        let newSize: NSSize
        
        if aspectRatio > 1 {
            // Landscape
            newSize = NSSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            // Portrait
            newSize = NSSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        // Use CGImage for GPU-accelerated resize
        guard let tiffData = self.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmapRep.cgImage else {
            return resizedProportionally(maxSize: newSize)
        }
        
        let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        context?.interpolationQuality = .high
        context?.draw(cgImage, in: CGRect(origin: .zero, size: newSize))
        
        guard let resizedCGImage = context?.makeImage() else {
            return resizedProportionally(maxSize: newSize)
        }
        
        return NSImage(cgImage: resizedCGImage, size: newSize)
    }
}

