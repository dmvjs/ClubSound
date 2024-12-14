import SwiftUI

struct TempoButtonRow: View {
    @ObservedObject var audioManager: AudioManager
    @StateObject private var wakeLockManager = WakeLockManager()

    var body: some View {
        VStack(spacing: 0) {
            // Buttons Section (Top Control + Tempo Buttons)
            VStack(spacing: 0) {
                // Top Row of Controls
                if UIScreen.main.bounds.width > 768 { // iPad Layout
                    HStack(spacing: 20) {
                        audioPickerButton()
                        pitchLockButton()
                        wakeLockButton()
                        playPauseButton()
                        tempoButtonRow() // Include tempo buttons in a single row for iPad
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                } else { // iPhone Layout
                    VStack(spacing: 20) {
                        HStack(spacing: 20) {
                            audioPickerButton()
                            pitchLockButton()
                            wakeLockButton()
                            playPauseButton()
                        }
                        .padding(.bottom, -13)
                        tempoButtonRow()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
            }
            .padding(.top, 10) // Adjust to keep it close to the top of the screen
        }
    }

    private func tempoButtonRow() -> some View {
        HStack(spacing: 12) {
            ForEach([69, 84, 94, 102, 112], id: \.self) { bpm in
                Button(action: {
                    updateBPM(to: bpm)
                }) {
                    bpmButtonLabel(for: bpm)
                }
            }
        }
    }

    private func updateBPM(to bpm: Int) {
        withAnimation {
            audioManager.bpm = Double(bpm)
            audioManager.restartAllPlayersFromBeginning()
        }
    }

    private func bpmButtonLabel(for bpm: Int) -> some View {
        Text("\(bpm)")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(audioManager.bpm == Double(bpm) ? .white : .gray)
            .frame(width: 60, height: 60)
            .background(
                Circle()
                    .fill(audioManager.bpm == Double(bpm) ? Color.blue : Color.gray.opacity(0.3))
            )
            .shadow(color: audioManager.bpm == Double(bpm) ? Color.blue.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
    }

    private func audioPickerButton() -> some View {
        AudioOutputPicker()
            .frame(width: 60, height: 60)
            .background(Circle().fill(Color.blue))
            .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    private func pitchLockButton() -> some View {
        Button(action: {
            audioManager.togglePitchLockWithoutRestart()
        }) {
            Image(systemName: audioManager.pitchLock ? "lock.fill" : "lock.open")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(audioManager.pitchLock ? Color.blue : Color.gray.opacity(0.3))
                )
                .shadow(color: audioManager.pitchLock ? Color.blue.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
        }
    }

    private func wakeLockButton() -> some View {
        Button(action: {
            if wakeLockManager.isWakeLockEnabled {
                wakeLockManager.disableWakeLock()
            } else {
                wakeLockManager.enableWakeLock()
            }
        }) {
            Image(systemName: wakeLockManager.isWakeLockEnabled ? "bolt.fill" : "bolt.slash")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(wakeLockManager.isWakeLockEnabled ? Color.green : Color.gray.opacity(0.3))
                )
                .shadow(color: wakeLockManager.isWakeLockEnabled ? Color.green.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
        }
    }

    private func playPauseButton() -> some View {
        Button(action: {
            audioManager.togglePlayback()
        }) {
            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(audioManager.isPlaying ? Color.green : Color.red)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
}
