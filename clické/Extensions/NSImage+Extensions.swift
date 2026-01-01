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
}

