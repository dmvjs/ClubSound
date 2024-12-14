import SwiftUI

struct BPMIndexView: View {
    let groupedSamples: [(Double, [(Int, [Sample])])]
    let activeBPM: Double? // Tracks the currently active BPM
    let onSelection: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(groupedSamples, id: \.0) { (bpm, _) in
                Button(action: {
                    onSelection(bpm)
                }) {
                    Text("\(Int(bpm))")
                        .font(.caption2)
                        .foregroundColor(activeBPM == bpm ? .black : .white)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(activeBPM == bpm ? Color.green : Color.blue)
                                .shadow(color: activeBPM == bpm ? Color.green.opacity(0.5) : .blue.opacity(0.4), radius: 5, x: 0, y: 2)
                        )
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.6))
        )
        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
    }
}
