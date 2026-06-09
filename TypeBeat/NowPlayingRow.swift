import SwiftUI

struct NowPlayingRow: View {
    let sample: Sample
    @Binding var volume: Float
    let remove: () -> Void
    let audioManager: AudioManager

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                // Background track
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 2)
                    .frame(width: 39, height: 39)

                // Progress ring — re-renders on every display frame while
                // playback is active, frozen otherwise.
                TimelineView(.animation(paused: !audioManager.isPlaying)) { _ in
                    let progress = audioManager.loopProgress()
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(sample.key.color, lineWidth: 3)
                        .rotationEffect(.degrees(-90))
                        .accessibilityValue(String(format: "%.2f", progress))
                        .accessibilityIdentifier("progress-ring-\(sample.id)")
                        .overlay(
                            Text(String(format: "%.4f", progress))
                                .opacity(0)
                                .accessibilityIdentifier("phase-\(sample.id)")
                        )
                }

                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 35, height: 35)
                    .overlay(
                        Text("\(sample.bpm, specifier: "%.0f")")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(sample.key.color)
                    )
            }
            .frame(width: 39, height: 39)
            .padding(5)

            Text(sample.title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()

            Slider(value: $volume, in: 0...1)
                .accentColor(sample.key.color)
                .frame(width: 150)
                .padding(8)
                .accessibilityIdentifier("Volume Slider")
        }
        .listRowSeparator(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.3))
        )
        .padding(.vertical, -4)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: remove) {
                Label("action.remove".localized, systemImage: "trash")
            }
            .accessibilityIdentifier("delete-button")
        }
    }
}
