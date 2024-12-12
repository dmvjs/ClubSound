import SwiftUI

struct BPMIndexView: View {
    let bpmValues: [Double]
    let activeBPM: Double?
    let onSelect: (Double) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(bpmValues, id: \.self) { bpm in
                Button(action: {
                    onSelect(bpm)
                }) {
                    Text("\(Int(bpm))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(activeBPM == bpm ? .white : .gray)
                        .frame(width: 50, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: activeBPM == bpm ? [Color.blue.opacity(0.6), Color.blue] : [Color.gray.opacity(0.1), Color.gray.opacity(0.2)]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: activeBPM == bpm ? Color.blue.opacity(0.4) : .clear, radius: 6, x: 0, y: 4)
                        )
                }
                .animation(.easeInOut, value: activeBPM)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.8))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        )
        .frame(width: 70)
    }
}

