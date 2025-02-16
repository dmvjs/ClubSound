import SwiftUI
import Combine

struct NowPlayingRow: View {
    let sample: Sample
    @Binding var volume: Float
    let remove: () -> Void
    let keyColor: Color
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 4) {
            // Circle with progress ring
            ZStack {
                Circle()
                    .trim(from: 0, to: CGFloat(audioManager.loopProgress()))  // Direct call instead of state
                    .stroke(Color.white.opacity(0.8), lineWidth: 3)
                    .rotationEffect(.degrees(-90))
                
                Circle()
                    .fill(sample.keyColor())
                    .frame(width: 33, height: 33)
                    .overlay(
                        Text("\(sample.bpm, specifier: "%.0f")")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 39, height: 39)
            .padding(5)

            Text(sample.title)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()

            // Volume Slider
            Slider(value: $volume, in: 0...1)
                .accentColor(sample.keyColor())
                .frame(width: 150)
                .padding(8)

        }
        .listRowSeparator(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6).opacity(0.4))
        )
        .padding(.vertical, -4) // Reduce vertical padding
        .listRowBackground(Color.black.opacity(0.9)) // Match list background
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                remove()
            } label: {
                Label("action.remove".localized, systemImage: "trash")
            }
        }
    }
}
