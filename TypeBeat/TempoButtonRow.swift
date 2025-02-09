import SwiftUI

struct TempoButtonRow: View {
    @ObservedObject var audioManager: AudioManager
    @StateObject private var wakeLockManager = WakeLockManager()
    @State private var showingLanguageMenu = false
    @Environment(\.dismiss) private var dismiss
    
    // Adjusted constants for better layout
    private let maxButtonSize: CGFloat = 56  // Increased from 52
    private let minButtonSpacing: CGFloat = 4  // Decreased from 8
    private let horizontalPadding: CGFloat = 8  // New constant for edge padding
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - (horizontalPadding * 2)
            let totalButtons = 9  // 5 control buttons + 4 tempo buttons
            let totalSpacing = minButtonSpacing * CGFloat(totalButtons - 1)
            let buttonSize = min(maxButtonSize, (availableWidth - totalSpacing) / CGFloat(totalButtons))
            
            HStack(spacing: minButtonSpacing) {
                // Control buttons group
                Group {
                    audioPickerButton(size: buttonSize)
                    languageButton(size: buttonSize)
                    pitchLockButton(size: buttonSize)
                    wakeLockButton(size: buttonSize)
                    playPauseButton(size: buttonSize)
                }
                
                // Tempo buttons group
                ForEach([69, 84, 94, 102], id: \.self) { bpm in
                    Button(action: {
                        updateBPM(to: bpm)
                    }) {
                        Text("\(bpm)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(audioManager.bpm == Double(bpm) ? .white : .gray)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(audioManager.bpm == Double(bpm) ? Color.blue : Color.clear)
                            )
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity)
        }
        .frame(height: maxButtonSize + 8)  // Increased height slightly
        .confirmationDialog(
            "Select Language",
            isPresented: $showingLanguageMenu,
            titleVisibility: .visible
        ) {
            Button("English") {
                changeLanguage("en")
            }
            Button("Español") {
                changeLanguage("es")
            }
            Button("Français") {
                changeLanguage("fr")
            }
            Button("Deutsch") {
                changeLanguage("de")
            }
            Button("日本語") {
                changeLanguage("ja")
            }
            Button("한국어") {
                changeLanguage("ko")
            }
            Button("中文") {
                changeLanguage("zh")
            }
        }
    }

    private func updateBPM(to bpm: Int) {
        withAnimation {
            audioManager.updateBPM(to: Double(bpm))
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

    private func languageButton(size: CGFloat) -> some View {
        Button(action: {
            showingLanguageMenu = true
        }) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                
                Image(systemName: "globe")
                    .font(.system(size: size * 0.5))
                    .foregroundColor(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("language.select".localized)
    }

    private func changeLanguage(_ code: String) {
        UserDefaults.standard.set(code, forKey: "AppLanguage")
        UserDefaults.standard.synchronize()
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            let rootView = SplashScreenView()
                .environment(\.locale, Locale(identifier: code))
            
            window.rootViewController = UIHostingController(rootView: rootView)
            
            UIView.transition(with: window,
                            duration: 0.3,
                            options: .transitionCrossDissolve,
                            animations: nil,
                            completion: nil)
        }
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
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel(audioManager.isPlaying ? "stop".localized : "play".localized)
        .animation(.easeInOut, value: audioManager.isPlaying)
    }
}
