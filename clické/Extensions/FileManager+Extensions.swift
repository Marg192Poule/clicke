import Foundation

extension FileManager {
    static var screenshotsDirectory: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Screenshots")
        
        // Check if directory exists and create it if not
        try? FileManager.default.createDirectory(at: url, 
                                                 withIntermediateDirectories: true)
        return url
    }
    
    func createScreenshotsDirectory() throws -> URL {
        let url = FileManager.screenshotsDirectory
        try createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

