import SwiftUI

struct TempoButtonGroup: View {
    let audioManager: AudioManager
    let buttonSize: CGFloat

    var body: some View {
        ForEach([69, 84, 94, 102], id: \.self) { bpm in
            Button(action: {
                audioManager.bpm = Double(bpm)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                bpmButtonLabel(for: bpm)
            }
        }
    }

    private func bpmButtonLabel(for bpm: Int) -> some View {
        let isActive = audioManager.bpm == Double(bpm)
        return Text("\(bpm)")
            .font(.system(size: buttonSize * 0.4, weight: .bold, design: .rounded))
            .foregroundColor(isActive ? .black : .white)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(width: buttonSize, height: buttonSize)
            .circleControlBackground(isActive: isActive)
            .shadow(color: isActive ? Color.green.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
    }
}
