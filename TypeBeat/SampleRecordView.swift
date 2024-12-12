import SwiftUI

struct SampleRecordView: View {
    let sample: Sample
    let isInPlaylist: Bool // Tracks if this sample is in the playlist
    let onSelect: () -> Void

    var body: some View {
        ZStack {
            // Background with gradient and edge-to-edge design
            LinearGradient(
                gradient: Gradient(colors: isInPlaylist
                    ? keyGradientColors(sample.key, intensity: 0.7)
                    : keyGradientColors(sample.key, intensity: 0.3)
                ),
                startPoint: .leading,
                endPoint: .trailing
            )
            .cornerRadius(10)
            .shadow(color: isInPlaylist ? Color.black.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                // Key indicator with bold circle
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: sample.keyGradientColors(intensity: 0.7)),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text("\(sample.key)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    )


                // Main text content
                Text(sample.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Spacer()

                // BPM with key color integration
                Text("\(sample.bpm, specifier: "%.0f") BPM")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [sample.keyColor().opacity(0.4), sample.keyColor().opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

            }
            .padding(.vertical, 8) // Slimmer vertical spacing
            .padding(.horizontal, 12)
        }
        .onTapGesture {
            onSelect()
        }
    }

    private func keyGradientColors(_ key: Int, intensity: Double) -> [Color] {
        let baseColor = sample.keyColor()
        return [
            baseColor.opacity(intensity),
            baseColor.opacity(intensity - 0.2),
            baseColor.opacity(intensity - 0.4)
        ]
    }
}
