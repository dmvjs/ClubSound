import SwiftUI
struct SampleRecordView: View {
    let sample: Sample
    let isInPlaylist: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    private func getKeyName(for key: Int) -> String {
        let keyNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return keyNames[key % 12]
    }

    var body: some View {
        ZStack {
            backgroundGradient()
                .cornerRadius(10)
                .shadow(color: isInPlaylist ? .black.opacity(0.3) : .clear,
                        radius: 8, x: 0, y: 4)

            HStack(spacing: 12) {
                keyIndicator()
                sampleInfo()
                Spacer()
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            .fill(sample.keyColor())
            .frame(width: 24, height: 24)
            .overlay(
                Text(getKeyName(for: sample.key))
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

    private func keyGradientColors(_ key: Int, intensity: Double) -> [Color] {
        let baseColor = sample.keyColor()
        return [
            baseColor.opacity(intensity),
            baseColor.opacity(max(intensity - 0.2, 0)),
            baseColor.opacity(max(intensity - 0.4, 0))
        ]
    }
} 