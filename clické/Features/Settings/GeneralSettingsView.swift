import SwiftUI
import AppKit
import ServiceManagement

// MARK: - General Settings

/// General tab: login item, Dock icon and capture sounds.
struct GeneralSettingsView: View {
    @Bindable var model: SettingsModel

    @State private var loginItemError: String?

    /// Slider value while dragging; saved to the settings when the drag ends.
    @State private var volume: Double
    @State private var isAdjustingVolume = false

    init(model: SettingsModel) {
        self.model = model
        _volume = State(initialValue: model.settings.soundEffectsVolume)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: launchAtLogin)
                Toggle("Show icon in Dock", isOn: $model.settings.showDockIcon)
            } footer: {
                footer
            }

            Section("Sounds") {
                Toggle("Play sound after capture", isOn: $model.settings.soundEffectsEnabled)

                LabeledContent("Sound") {
                    HStack(spacing: 8) {
                        Picker("Sound", selection: captureSound) {
                            ForEach(CaptureSound.allCases) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()

                        Button {
                            playPreview()
                        } label: {
                            Label("Play Sound", systemImage: "play.fill")
                                .labelStyle(.iconOnly)
                        }
                        .help("Play the selected sound")
                    }
                }
                .disabled(!model.settings.soundEffectsEnabled)

                LabeledContent("Volume") {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Slider(value: volumeBinding, in: 0...1) { editing in
                            isAdjustingVolume = editing
                            if !editing {
                                model.settings.soundEffectsVolume = volume
                                playPreview()
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Volume")
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(width: 220)
                }
                .disabled(!model.settings.soundEffectsEnabled)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onChange(of: model.settings.soundEffectsVolume) { _, newValue in
            if !isAdjustingVolume { volume = newValue }
        }
        .alert(
            "Couldn’t Change Login Item",
            isPresented: Binding(
                get: { loginItemError != nil },
                set: { if !$0 { loginItemError = nil } }
            ),
            presenting: loginItemError
        ) { _ in
            Button("Open Login Items Settings") {
                SMAppService.openSystemSettingsLoginItems()
            }
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        let needsApproval = model.loginItemStatus == .requiresApproval
        let dockIconHidden = !model.settings.showDockIcon
        if needsApproval || dockIconHidden {
            VStack(alignment: .leading, spacing: 6) {
                if needsApproval {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Clické needs your approval in System Settings to open at login.")
                        Spacer()
                        Button("Open Login Items Settings") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .controlSize(.small)
                    }
                }
                if dockIconHidden {
                    Text("Clické stays available from its icon in the menu bar.")
                }
            }
        }
    }

    // MARK: Bindings

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { model.loginItemStatus == .enabled || model.loginItemStatus == .requiresApproval },
            set: { setLaunchAtLogin($0) }
        )
    }

    private var captureSound: Binding<CaptureSound> {
        Binding(
            get: { model.settings.captureSound },
            set: { newValue in
                model.settings.captureSound = newValue
                playPreview()
            }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { volume },
            set: { newValue in
                volume = newValue
                // Keyboard / VoiceOver adjustments don't send editing events: save them right away.
                if !isAdjustingVolume {
                    model.settings.soundEffectsVolume = newValue
                }
            }
        )
    }

    // MARK: Actions

    private func playPreview() {
        SoundManager.shared.playSound(model.settings.captureSound, volume: Float(volume))
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        model.refreshSystemStatus()
    }
}
