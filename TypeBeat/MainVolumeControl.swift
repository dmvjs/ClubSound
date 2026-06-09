import SwiftUI

struct MainVolumeControl: View {
    @Bindable var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                // Background track
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 2)
                    .frame(width: 39, height: 39)

                // Progress ring — driven by the display link while playing.
                TimelineView(.animation(paused: !audioManager.isPlaying)) { _ in
                    Circle()
                        .trim(from: 0, to: CGFloat(audioManager.loopProgress()))
                        .stroke(Color.accentColor, lineWidth: 2)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 39, height: 39)
                }

                // Center circle with BPM label
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 35, height: 35)
                    .overlay(
                        Text("\(Int(audioManager.bpm))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    )
            }
            .padding(5)

            Text("main.volume".localized)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .accessibilityIdentifier("Main Volume")
            Spacer()

            Slider(value: $audioManager.masterVolume, in: 0...1)
                .accentColor(.accentColor)
                .frame(width: 150)
                .padding(8)
                .accessibilityIdentifier("Main Volume Slider")
        }
        .glassBackground(cornerRadius: 16)
        .padding(.vertical, -2)
    }
}
