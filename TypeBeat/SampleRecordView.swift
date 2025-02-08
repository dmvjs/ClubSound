import SwiftUI
struct SampleRecordView: View {
    let sample: Sample
    let isInPlaylist: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack {
            backgroundGradient()
                .cornerRadius(10)
                .shadow(color: isInPlaylist ? .black.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)

            HStack(spacing: 12) {
                keyIndicator()
                sampleInfo()
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .onTapGesture {
            isInPlaylist ? onRemove() : onSelect()
        }
    }

    private func backgroundGradient() -> LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: isInPlaylist
                ? keyGradientColors(sample.key, intensity: 0.7)
                : keyGradientColors(sample.key, intensity: 0.3)),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func keyIndicator() -> some View {
        Circle()
            .fill(sample.keyColor()) // Use the existing keyColor method
            .frame(width: 24, height: 24)
            .overlay(
                Text("\(getKeyName(for: sample.key))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            )
    }

    private func sampleInfo() -> some View {
        Text(sample.title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(2)
    }

    private func keyGradientColors(_ key: MusicKey, intensity: Double) -> [Color] {
        let baseColor = sample.keyColor()
        return [
            baseColor.opacity(intensity),
            baseColor.opacity(intensity - 0.2),
            baseColor.opacity(intensity - 0.4)
        ]
    }

    private func getKeyName(for key: MusicKey) -> String {
        return key.name
    }
}
