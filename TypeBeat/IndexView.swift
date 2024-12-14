import SwiftUI
struct IndexView: View {
    let groupedSamples: [(Double, [(Int, [Sample])])]
    let onSelection: (Double, Int?) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(groupedSamples, id: \.0) { (bpm, keyGroups) in
                VStack(spacing: 3) {
                    // BPM Label
                    Button(action: {
                        onSelection(bpm, nil)
                    }) {
                        Text("\(Int(bpm))")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.blue))
                    }

                    // Key Labels for Each BPM
                    ForEach(keyGroups, id: \.0) { (key, _) in
                        Button(action: {
                            onSelection(bpm, key)
                        }) {
                            Circle()
                                .fill(keyColor(for: key))
                                .overlay(
                                    Text("\(key)")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                )
                                .frame(width: 15, height: 15) // Smaller for compactness
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.6))
        )
        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
    }

    private func keyColor(for key: Int) -> Color {
        return Sample(id: 0, title: "", key: key, bpm: 0, fileName: "").keyColor()
    }
}
