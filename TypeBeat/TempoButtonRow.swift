import SwiftUI

struct TempoButtonRow: View {
    @ObservedObject var audioManager: AudioManager
    @StateObject private var wakeLockManager = WakeLockManager()
    
    private let maxButtonSize: CGFloat = 52
    private let minButtonSpacing: CGFloat = 8
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 24
            let totalButtons = 9
            let totalSpacing = minButtonSpacing * CGFloat(totalButtons - 1)
            let buttonSize = min(maxButtonSize, (availableWidth - totalSpacing) / CGFloat(totalButtons))
            
            HStack(spacing: minButtonSpacing) {
                // Control buttons group
                audioPickerButton(size: buttonSize)
                pitchLockButton(size: buttonSize)
                wakeLockButton(size: buttonSize)
                playPauseButton(size: buttonSize)
                
                // Tempo buttons group
                ForEach([69, 84, 94, 102, 112], id: \.self) { bpm in
                    Button(action: {
                        updateBPM(to: bpm)
                    }) {
                        bpmButtonLabel(for: bpm, size: buttonSize)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
        }
        .frame(height: maxButtonSize + 4)
    }

    private func updateBPM(to bpm: Int) {
        withAnimation {
            audioManager.bpm = Double(bpm)
            audioManager.restartAllPlayersFromBeginning()
        }
    }

    private func bpmButtonLabel(for bpm: Int, size: CGFloat) -> some View {
        let isActive = audioManager.bpm == Double(bpm)
        
        return ZStack {
            Circle()
                .fill(isActive ? Color.green : Color.gray.opacity(0.3))
            
            Text("\(bpm)")
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .foregroundColor(isActive ? .black : .white)
        }
        .frame(width: size, height: size)
        .shadow(color: isActive ? Color.green.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
    }

    private func audioPickerButton(size: CGFloat) -> some View {
        AudioOutputPicker()
            .frame(width: size, height: size)
            .background(Circle().fill(Color.blue))
            .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    private func pitchLockButton(size: CGFloat) -> some View {
        Button(action: {
            audioManager.togglePitchLockWithoutRestart()
        }) {
            Image(systemName: audioManager.pitchLock ? "lock.fill" : "lock.open")
                .font(.system(size: size * 0.5))
                .foregroundColor(audioManager.pitchLock ? .black : .white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(audioManager.pitchLock ? Color.green : Color.gray.opacity(0.3))
                )
                .shadow(color: audioManager.pitchLock ? Color.green.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
        }
    }

    private func wakeLockButton(size: CGFloat) -> some View {
        Button(action: {
            if wakeLockManager.isWakeLockEnabled {
                wakeLockManager.disableWakeLock()
            } else {
                wakeLockManager.enableWakeLock()
            }
        }) {
            Image(systemName: wakeLockManager.isWakeLockEnabled ? "bolt.fill" : "bolt.slash")
                .font(.system(size: size * 0.5))
                .foregroundColor(wakeLockManager.isWakeLockEnabled ? .black : .white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(wakeLockManager.isWakeLockEnabled ? Color.green : Color.gray.opacity(0.3))
                )
                .shadow(color: wakeLockManager.isWakeLockEnabled ? Color.green.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
        }
    }

    private func playPauseButton(size: CGFloat) -> some View {
        Button(action: {
            withAnimation {
                audioManager.togglePlayback()
            }
        }) {
            ZStack {
                // Main circle
                Circle()
                    .fill(audioManager.isPlaying ? Color.green : Color.red)
                
                // Play/Stop icon
                Image(systemName: audioManager.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundColor(audioManager.isPlaying ? .black : .white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .animation(.easeInOut, value: audioManager.isPlaying)
    }
}
