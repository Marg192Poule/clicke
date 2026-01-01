import Foundation

extension FileManager {
    static var screenshotsDirectory: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Screenshots")
        
        // on verif si le dossier existe et sinon on le créer
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

