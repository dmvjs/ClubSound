import SwiftUI
import Combine
import QuartzCore

struct NowPlayingRow: View {
    let sample: Sample
    @Binding var volume: Float
    let remove: () -> Void
    let keyColor: Color
    @ObservedObject var audioManager: AudioManager
    
    @State private var progress: Double = 0
    
    var body: some View {
        HStack(spacing: 4) {
            // Circle with progress ring
            ZStack {
                // Background track (iOS system gray)
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 2)
                    .frame(width: 39, height: 39)
                
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(sample.keyColor(), lineWidth: 3)
                    .rotationEffect(.degrees(-90))
                
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 35, height: 35)
                    .overlay(
                        Text("\(sample.bpm, specifier: "%.0f")")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(sample.keyColor())
                    )
            }
            .frame(width: 39, height: 39)
            .padding(5)
            // Update the progress using a Timer publisher at ~60fps
            .onReceive(Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()) { _ in
                if audioManager.isPlaying {
                    progress = audioManager.loopProgress()
                } else {
                    progress = 0
                }
            }

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
                .accessibilityIdentifier("Volume Slider")
        }
        .listRowSeparator(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6).opacity(0.4))
        )
        .padding(.vertical, -4)
        .listRowBackground(Color.black.opacity(0.9))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                remove()
            } label: {
                Label("action.remove".localized, systemImage: "trash")
            }
        }
    }
}

// Separate class to handle DisplayLink
class ProgressUpdater: ObservableObject {
    private var displayLink: CADisplayLink?
    
    func start(update: @escaping () -> Void) {
        displayLink?.invalidate()
        
        let target = DisplayLinkTarget(updateHandler: update)
        let displayLink = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.handleUpdate))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
        self.displayLink = displayLink
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
}

// Helper class to handle the @objc requirement
class DisplayLinkTarget {
    let updateHandler: () -> Void
    
    init(updateHandler: @escaping () -> Void) {
        self.updateHandler = updateHandler
    }
    
    @objc func handleUpdate() {
        updateHandler()
    }
}
