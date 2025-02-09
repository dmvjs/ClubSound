import SwiftUI
struct KeyIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeKey: MusicKey?
    let activeBPM: Double?
    let onSelection: (MusicKey) -> Void
    
    private let keys = MusicKey.allCases
    private let keyNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(MusicKey.allCases, id: \.self) { key in
                keyButton(for: key)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
        )
        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
        .frame(height: UIScreen.main.bounds.height * 0.33)
        .padding(.top, 0)
    }
    
    private func keyButton(for key: MusicKey) -> some View {
        Button(action: {
            onSelection(key)
        }) {
            Text(key.name)
                .font(.caption2)
                .foregroundColor(activeKey == key ? .black : .white)
                .frame(width: 36, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(activeKey == key ? Sample(id: 0, title: "", key: key, bpm: 0, fileName: "").keyColor() : Color.gray.opacity(0.3))
                )
        }
    }
} 
