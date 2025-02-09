import SwiftUI
import Combine

struct NowPlayingRow: View {
    let sample: Sample
    @Binding var volume: Float
    let remove: () -> Void
    let keyColor: Color
    @ObservedObject var audioManager: AudioManager

    @State private var progress: Double = 0.0
    @State private var timer: AnyCancellable?

    var body: some View {
        HStack(spacing: 4) {
            // Circle with progress ring
            ZStack {
                // Progress ring - now white with opacity
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color.white.opacity(0.8), lineWidth: 3)  // Changed to white
                    .rotationEffect(.degrees(-90))  // Start from top
                
                // Main circle (keeps original key color)
                Circle()
                    .fill(sample.keyColor())
                    .frame(width: 33, height: 33)
                    .overlay(
                        Text("\(sample.bpm, specifier: "%.0f")")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 39, height: 39)  // Slightly larger to accommodate progress ring
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
        .onAppear {
            // Start the timer when the view appears
            timer = Timer.publish(every: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    let newProgress = audioManager.loopProgress(for: sample.id)
                    withAnimation(.linear(duration: 0.1)) {
                        self.progress = newProgress  // Now mutable
                    }
                }
        }
        .onDisappear {
            // Invalidate the timer when the view disappears
            timer?.cancel()
        }
    }
}
