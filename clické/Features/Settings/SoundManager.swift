import AppKit

// MARK: - Sound Manager

/// Plays the capture sound effects (macOS system sounds).
final class SoundManager {
    static let shared = SoundManager()

    /// The sound being played. `NSSound` stops when it's deallocated, so it's kept alive here.
    private var currentSound: NSSound?

    private init() {}

    /// Plays the specified capture sound at the given volume.
    /// - Parameters:
    ///   - sound: The capture sound to play.
    ///   - volume: The volume level (0.0 to 1.0).
    func playSound(_ sound: CaptureSound, volume: Float) {
        guard let nsSound = Self.makeSound(for: sound) else { return }

        currentSound?.stop()
        nsSound.volume = min(max(volume, 0), 1)
        currentSound = nsSound
        nsSound.play()
    }

    /// Loads a fresh instance of the system sound, so overlapping plays and volume changes don't interfere.
    private static func makeSound(for sound: CaptureSound) -> NSSound? {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(sound.systemSoundName).aiff")
        if let nsSound = NSSound(contentsOf: url, byReference: true) {
            return nsSound
        }
        // Fallback: let AppKit search the standard sound folders. `NSSound(named:)` returns a shared
        // instance, so play a copy of it.
        return NSSound(named: sound.systemSoundName)?.copy() as? NSSound
    }
}
