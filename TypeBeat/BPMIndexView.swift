import SwiftUI

struct BPMIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeBPM: Double? // Tracks the currently active BPM
    let onSelection: (Double) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(groupedSamples, id: \.0) { bpm, _ in
                bpmButton(for: bpm)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
        )
        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
    }
    
    private func bpmButton(for bpm: Double) -> some View {
        Button(action: {
            onSelection(bpm)
        }) {
            let isActive = activeBPM == bpm
            let backgroundColor = isActive ? Color.green : Color.gray.opacity(0.3)
            
            Text("\(Int(bpm))")
                .font(.caption2)
                .foregroundColor(isActive ? .black : .white)
                .frame(width: 36, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(backgroundColor)
                )
        }
    }
}

