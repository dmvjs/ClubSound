import SwiftUI

struct ControlButtonGroup: View {
    let audioManager: AudioManager
    @Bindable var wakeLockManager: WakeLockManager
    @Binding var showingLanguageSelection: Bool
    @Binding var breatheScale: CGFloat
    let buttonSize: CGFloat
    
    var body: some View {
        Group {
            audioPickerButton
            playPauseButton
            pitchLockButton
            wakeLockButton
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
        }
        .accessibilityLabel(audioManager.isPlaying ? "stop".localized : "play".localized)
        .accessibilityIdentifier("play-button")
        .animation(.easeInOut, value: audioManager.isPlaying)
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

    private var wakeLockButton: some View {
        Button {
            if wakeLockManager.isWakeLockEnabled {
                wakeLockManager.disableWakeLock()
            } else {
                wakeLockManager.enableWakeLock()
            }
        } label: {
            Image(systemName: wakeLockManager.isWakeLockEnabled ? "bolt.fill" : "bolt.slash")
                .font(.system(size: buttonSize * 0.5))
                .foregroundColor(wakeLockManager.isWakeLockEnabled ? .black : .white)
                .frame(width: buttonSize, height: buttonSize)
                .circleControlBackground(isActive: wakeLockManager.isWakeLockEnabled)
                .shadow(color: wakeLockManager.isWakeLockEnabled ? Color.green.opacity(0.4) : .clear, radius: 7, x: 0, y: 4)
        }
        .accessibilityLabel("wake_lock".localized)
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

