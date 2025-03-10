import SwiftUI

struct TempoButtonGroup: View {
    @ObservedObject var audioManager: AudioManager
    let buttonSize: CGFloat
    
    var body: some View {
        ForEach([69, 84, 94, 102], id: \.self) { bpm in
            Button(action: {
                // Ensure BPM updates happen on main thread
                DispatchQueue.main.async {
                    // Update BPM without stopping playback
                    audioManager.updateBPM(to: Double(bpm))
                    
                    // Provide haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }
            }) {
                bpmButtonLabel(for: bpm)
            }
        }
    }
    
    private func bpmButtonLabel(for bpm: Int) -> some View {
        let isActive = audioManager.bpm == Double(bpm)
        
        return ZStack {
            Circle()
                .fill(isActive ? Color.green : Color.gray.opacity(0.3))
            
            Text("\(bpm)")
                .font(.system(size: buttonSize * 0.4, weight: .bold, design: .rounded))
                .foregroundColor(isActive ? .black : .white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: buttonSize, height: buttonSize)
        .shadow(color: isActive ? Color.green.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
    }
} 