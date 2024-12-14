import SwiftUI

struct NowPlayingRow: View {
    let sample: Sample
    @Binding var volume: Float
    let remove: () -> Void
    let keyColor: Color

    var body: some View {
        HStack(spacing: 8) {
            // Highlighted circle with consistent color
            Circle()
                .fill(sample.keyColor())
                .frame(width: 33, height: 33)
                .overlay(
                    Text("\(sample.bpm, specifier: "%.0f")")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                )

            Text(sample.title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()

            // Volume Slider
            Slider(value: $volume, in: 0...1)
                .accentColor(sample.keyColor())
                .frame(width: 150)
        }
        .listRowSeparator(.hidden)
        .padding(8) // Ensure padding matches the list style
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6).opacity(0.4))
        )
        .listRowBackground(Color.black.opacity(0.9)) // Match list background
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                remove()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}
