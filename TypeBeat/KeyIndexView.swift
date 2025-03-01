import SwiftUI

struct KeyIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeKey: MusicKey?
    let activeBPM: Double?
    let onSelection: (MusicKey) -> Void
    
    // Explicitly track selection state internally
    @State private var selectedKey: MusicKey?
    
    // Fixed width for text and tap target
    private let textWidth: CGFloat = 16
    private let tapTargetWidth: CGFloat = 44
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(uniqueKeys, id: \.self) { key in
                let isSelected = isThisKeySelected(key)
                
                Text(key.localizedName)
                    .font(.system(size: 13, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : key.color)
                    .frame(width: textWidth)
                    .frame(maxWidth: tapTargetWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            // Force update the selection
                            if selectedKey == key {
                                // If already selected, do nothing
                            } else {
                                selectedKey = key
                                onSelection(key)
                            }
                        }
                    }
                    .accessibilityIdentifier("key-header-\(key.rawValue)")
            }
        }
        .frame(width: tapTargetWidth)
        .onAppear {
            // Initialize with activeKey, but only if it's not already set
            if selectedKey == nil {
                selectedKey = activeKey
            }
        }
        .onChange(of: activeKey) { newValue in
            selectedKey = newValue
        }
    }
    
    // Simplified selection check
    private func isThisKeySelected(_ key: MusicKey) -> Bool {
        return selectedKey == key
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
