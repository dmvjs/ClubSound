import SwiftUI

struct KeyIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeKey: MusicKey?
    let selectedBPM: Double?  // Renamed from activeBPM to selectedBPM for clarity
    let onSelection: (MusicKey) -> Void
    
    // Explicitly track selection state internally
    @State private var selectedKey: MusicKey?
    
    // Fixed width for text and tap target
    private let textWidth: CGFloat = 16
    private let tapTargetWidth: CGFloat = 44
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(availableKeysForSelectedBPM, id: \.self) { key in
                let isSelected = isThisKeySelected(key)
                
                Text(key.localizedName)
                    .font(.system(size: 11, weight: .semibold))
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
        .onChange(of: selectedBPM) { _ in
            // When BPM selection changes, we may need to update the selected key
            // if it's not available in the new BPM
            if let selectedKey = selectedKey, !availableKeysForSelectedBPM.contains(selectedKey) {
                // If the currently selected key isn't available for the new BPM,
                // select the first available key instead
                if let firstKey = availableKeysForSelectedBPM.first {
                    self.selectedKey = firstKey
                    onSelection(firstKey)
                }
            }
        }
    }
    
    // Simplified selection check
    private func isThisKeySelected(_ key: MusicKey) -> Bool {
        return selectedKey == key
    }
    
    // Get only the keys available for the selected BPM
    private var availableKeysForSelectedBPM: [MusicKey] {
        if let selectedBPM = selectedBPM {
            // Find the keys available for the selected BPM
            if let bpmGroup = groupedSamples.first(where: { abs($0.0 - selectedBPM) < 0.01 }) {
                return bpmGroup.1.map { $0.0 }.sorted()
            }
        }
        
        // If no BPM selected or no matching group, return all unique keys
        return uniqueKeys
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
