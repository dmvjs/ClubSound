import SwiftUI

struct TempoButtonRow: View {
    @ObservedObject var audioManager: AudioManager
    @StateObject private var wakeLockManager = WakeLockManager()
    @Environment(\.dismiss) private var dismiss
    @State private var showingLanguageSelection = false
    @State private var breatheScale: CGFloat = 1.0
    
    // Adjusted constants for better layout
    private let maxButtonSize: CGFloat = 56  // Increased from 52
    private let minButtonSpacing: CGFloat = 4  // Decreased from 8
    private let horizontalPadding: CGFloat = 8  // New constant for edge padding
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - (horizontalPadding * 2)
            let totalButtons = 9
            let totalSpacing = minButtonSpacing * CGFloat(totalButtons - 1)
            let buttonSize = min(maxButtonSize, (availableWidth - totalSpacing) / CGFloat(totalButtons))
            
            HStack(spacing: minButtonSpacing) {
                // Control buttons group
                Group {
                    audioPickerButton(size: buttonSize)
                    playPauseButton(size: buttonSize)
                    pitchLockButton(size: buttonSize)
                    wakeLockButton(size: buttonSize)
                    languageButton(size: buttonSize)
                }
                
                // Tempo buttons group
                ForEach([69, 84, 94, 102], id: \.self) { bpm in
                    Button(action: {
                        DispatchQueue.global(qos: .userInitiated).async {
                            audioManager.updateBPM(to: Double(bpm))
                            DispatchQueue.main.async {
                                audioManager.objectWillChange.send()
                            }
                        }
                    }) {
                        Text("\(bpm)")
                            .font(.system(size: buttonSize * 0.4))
                            .foregroundColor(audioManager.bpm == Double(bpm) ? .black : .white)
                            .frame(width: buttonSize, height: buttonSize)
                            .background(
                                Circle()
                                    .fill(audioManager.bpm == Double(bpm) ? Color.green : Color.gray.opacity(0.3))
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
        .frame(height: maxButtonSize)
        .sheet(isPresented: $showingLanguageSelection) {
            LanguageSelectionView()
        }
    }

    private func bpmButtonLabel(for bpm: Int, size: CGFloat) -> some View {
        let isActive = audioManager.bpm == Double(bpm)
        
        return ZStack {
            Circle()
                .fill(isActive ? Color.green : Color.gray.opacity(0.3))
            
            Text("\(bpm)")  // Simplified from "bpm_format"
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundColor(isActive ? .black : .white)
                .minimumScaleFactor(0.5)  // Allow text to scale down if needed
                .lineLimit(1)
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
        .accessibilityLabel("lock_pitch".localized)
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
        .accessibilityLabel("wake_lock".localized)
    }

    private func playPauseButton(size: CGFloat) -> some View {
        Button(action: {
            withAnimation {
                audioManager.togglePlayback()
            }
        }) {
            ZStack {
                Circle()
                    .fill(audioManager.isPlaying ? Color.green : Color.red)
                
                Image(systemName: audioManager.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundColor(audioManager.isPlaying ? .black : .white)
            }
            .frame(width: size, height: size)
            .scaleEffect(audioManager.isPlaying ? 1.0 : breatheScale)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel(audioManager.isPlaying ? "stop".localized : "play".localized)
        .animation(.easeInOut, value: audioManager.isPlaying)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                breatheScale = 1.1
            }
        }
    }

    private func languageButton(size: CGFloat) -> some View {
        Button(action: {
            // Just show the sheet without affecting audio state
            showingLanguageSelection = true
        }) {
            Image(systemName: "globe")
                .font(.system(size: size * 0.5))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.gray.opacity(0.3)))
        }
    }
}
