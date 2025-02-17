import SwiftUI

struct KeyIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeKey: MusicKey?
    let activeBPM: Double?
    let onSelection: (MusicKey) -> Void
    
    // Fixed width for text and tap target
    private let textWidth: CGFloat = 16
    private let tapTargetWidth: CGFloat = 44
    
    @State private var selectedKey: MusicKey?
    @State private var showingIndicator = false
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(uniqueKeys, id: \.self) { key in
                Text(key.localizedName)
                    .font(.system(size: 11, weight: .semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundColor(activeKey == key ? key.color : key.color.opacity(0.5))
                    .frame(width: textWidth)
                    .frame(maxWidth: tapTargetWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onSelection(key)
                        }
                    }
                    .accessibilityIdentifier("key-header-\(key.rawValue)")
            }
        }
        .frame(width: tapTargetWidth)
    }
    
    private var uniqueKeys: [MusicKey] {
        let keys = groupedSamples.flatMap { _, keyGroups in
            keyGroups.map { $0.0 }
        }
        return Array(Set(keys)).sorted()
    }
}

extension MusicKey {
    var color: Color {
        Sample(id: 0, title: "", key: self, bpm: 0, fileName: "").keyColor()
    }
} 
