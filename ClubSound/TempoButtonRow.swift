import SwiftUI

struct TempoButtonRow: View {
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 12) {
            ForEach([69, 84, 94, 102], id: \.self) { bpm in
                Button(action: {
                    updateBPM(to: bpm)
                }) {
                    bpmButtonLabel(for: bpm)
                }
            }

            Spacer()

            pitchLockButton()

            wakeLockButton()
        }
        .padding(.horizontal)
        .padding(.top, 60)
        .padding(.bottom, 10)
        .background(
            Color.black.opacity(0.9)
                .edgesIgnoringSafeArea(.top)
        )
    }

    private func updateBPM(to bpm: Int) {
        withAnimation {
            audioManager.bpm = Double(bpm)
        }
    }

    private func bpmButtonLabel(for bpm: Int) -> some View {
        Text("\(bpm)")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(audioManager.bpm == Double(bpm) ? .white : .gray)
            .frame(width: 50, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(audioManager.bpm == Double(bpm) ? Color.blue : Color.gray.opacity(0.2))
            )
            .shadow(color: audioManager.bpm == Double(bpm) ? Color.blue.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
    }

    private func pitchLockButton() -> some View {
        Button(action: {
            audioManager.togglePitchLockWithoutRestart()
        }) {
            Image(systemName: audioManager.pitchLock ? "lock.fill" : "lock.open")
                .font(.system(size: 22))
                .foregroundColor(.white)
                .padding(8)
                .background(
                    Circle()
                        .fill(audioManager.pitchLock ? Color.blue : Color.gray.opacity(0.2))
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
            Image(systemName: wakeLockManager.isWakeLockEnabled ? "power" : "bolt.slash")
                .font(.system(size: 22))
                .foregroundColor(.white)
                .padding(8)
                .background(
                    Circle()
                        .fill(wakeLockManager.isWakeLockEnabled ? Color.green : Color.gray.opacity(0.2))
                )
                .shadow(color: wakeLockManager.isWakeLockEnabled ? Color.green.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
        }
    }

    @StateObject private var wakeLockManager = WakeLockManager()
}
