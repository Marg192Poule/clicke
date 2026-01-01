import SwiftUI

struct SoundSectionView: View {
    @Binding var soundEnabled: Bool
    @Binding var volume: Double
    
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Effets sonores", isOn: $soundEnabled)
                    Text("Activer les sons lors des captures")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: "speaker.wave.2.fill")
            }
            
            if soundEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int(volume * 100))%")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $volume, in: 0...1)
                }
            }
        } header: {
            Text("Son")
        }
    }
}

