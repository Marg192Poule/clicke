import SwiftUI
import AVFoundation

struct SoundSectionView: View {
    @Binding var soundEnabled: Bool
    @Binding var volume: Double
    @Binding var selectedSound: CaptureSound
    
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("sound effects", isOn: $soundEnabled)
                    Text("activate sound effects when capturing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: "speaker.wave.2.fill")
            }
            
            if soundEnabled {
                // Choix du son
                Label {
                    HStack {
                        Text("capture sound")
                        Spacer()
                        Picker("", selection: $selectedSound) {
                            ForEach(CaptureSound.allCases) { sound in
                                Text(sound.rawValue).tag(sound)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        
                        // Bouton pour tester le son
                        Button(action: {
                            playSoundPreview()
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                        .help("test the sound")
                    }
                } icon: {
                    Image(systemName: "music.note")
                }
                
                // Contrôle du volume
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "speaker.wave.1.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                        Text("volume")
                        Spacer()
                        Text("\(Int(volume * 100))%")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $volume, in: 0...1)
                }
            }
        } header: {
            Text("sound")
        } footer: {
            if soundEnabled {
                Text("choose a sound that will be played each time a capture is made")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func playSoundPreview() {
        SoundManager.shared.playSound(selectedSound, volume: Float(volume))
    }
}

// Manager pour jouer les sons système
class SoundManager {
    static let shared = SoundManager()
    
    private var audioPlayer: AVAudioPlayer?
    
    func playSound(_ sound: CaptureSound, volume: Float) {
        // Utiliser les sons système de macOS
        let soundName = sound.systemSoundName
        
        // Chemins possibles pour les sons système
        let possiblePaths = [
            "/System/Library/Sounds/\(soundName).aiff",
            "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/\(soundName).aif"
        ]
        
        for path in possiblePaths {
            if let url = URL(string: "file://\(path)"),
               FileManager.default.fileExists(atPath: path) {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: url)
                    audioPlayer?.volume = volume
                    audioPlayer?.play()
                    return
                } catch {
                    continue
                }
            }
        }
        
        // Fallback: utiliser NSSound pour les sons système
        if let sound = NSSound(named: soundName) {
            sound.volume = volume
            sound.play()
        }
    }
}

