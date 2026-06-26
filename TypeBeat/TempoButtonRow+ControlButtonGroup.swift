import SwiftUI

struct ControlButtonGroup: View {
    let audioManager: AudioManager
    @Binding var showingLanguageSelection: Bool
    @Binding var breatheScale: CGFloat
    let buttonSize: CGFloat

    var body: some View {
        Group {
            audioPickerButton
            AutoModeButton(audioManager: audioManager, buttonSize: buttonSize)
            playPauseButton
            pitchLockButton
            languageButton
        }
    }

    private var audioPickerButton: some View {
        AudioOutputPicker()
            .frame(width: buttonSize, height: buttonSize)
            .background(Circle().fill(Color.blue))
            .shadow(color: .blue.opacity(0.4), radius: 7, x: 0, y: 4)
    }

    private var playPauseButton: some View {
        let buttonSize = max(self.buttonSize, 44) // Ensure minimum size

        return Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            if audioManager.isPlaying {
                audioManager.stopAllPlayers()
            } else {
                Task { await audioManager.playWithDefaults() }
            }
        }) {
            ZStack {
                Circle()
                    .fill(audioManager.isPlaying ? Color.red : Color.green)

                Image(systemName: audioManager.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: buttonSize * 0.5))
                    .foregroundColor(.black)
            }
            .frame(width: buttonSize, height: buttonSize)
            .scaleEffect(audioManager.isPlaying ? 1.0 : breatheScale)
            .shadow(color: .black.opacity(0.3), radius: 7, x: 0, y: 4)
            .overlay(alignment: .topTrailing) {
                volumeBadge(buttonSize: buttonSize)
            }
        }
        .accessibilityLabel(audioManager.isPlaying ? "stop".localized : "play".localized)
        .accessibilityIdentifier("play-button")
        .animation(.easeInOut, value: audioManager.isPlaying)
        .animation(.easeInOut(duration: 0.25), value: audioManager.volumeBadge)
    }

    @ViewBuilder
    private func volumeBadge(buttonSize: CGFloat) -> some View {
        let badgeSize = buttonSize * 0.42
        switch audioManager.volumeBadge {
        case .muted:
            VolumeBadgeDot(color: .red, iconColor: .black, icon: "speaker.slash.fill", size: badgeSize)
                .offset(x: badgeSize * 0.20, y: -badgeSize * 0.20)
                .transition(.scale.combined(with: .opacity))
        case .low:
            VolumeBadgeDot(color: .yellow, iconColor: .black, icon: "speaker.wave.1.fill", size: badgeSize)
                .offset(x: badgeSize * 0.20, y: -badgeSize * 0.20)
                .transition(.scale.combined(with: .opacity))
        case .ok:
            EmptyView()
        }
    }

    private var pitchLockButton: some View {
        Button {
            audioManager.pitchLock.toggle()
        } label: {
            Image(systemName: audioManager.pitchLock ? "lock.fill" : "lock.open")
                .font(.system(size: buttonSize * 0.5))
                .foregroundColor(audioManager.pitchLock ? .black : .white)
                .frame(width: buttonSize, height: buttonSize)
                .circleControlBackground(isActive: audioManager.pitchLock)
                .shadow(color: audioManager.pitchLock ? Color.green.opacity(0.4) : .clear, radius: 7, x: 0, y: 4)
        }
        .accessibilityLabel("lock_pitch".localized)
    }

    private var languageButton: some View {
        Button {
            showingLanguageSelection = true
        } label: {
            Image(systemName: "globe")
                .font(.system(size: buttonSize * 0.5))
                .foregroundColor(.white)
                .frame(width: buttonSize, height: buttonSize)
                .circleControlBackground(isActive: false)
        }
    }
}

/// Tiny iOS-notification-style badge that lives in the top-right of the play
/// button when device output volume is muted (red) or one notch above (yellow).
/// Tells the user the app isn't broken — their phone is silenced.
private struct VolumeBadgeDot: View {
    let color: Color
    let iconColor: Color
    let icon: String
    let size: CGFloat

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundColor(iconColor)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(Color.black.opacity(0.85), lineWidth: 1.5))
            .shadow(color: color.opacity(0.5), radius: 3, x: 0, y: 1)
            .allowsHitTesting(false)
    }
}
