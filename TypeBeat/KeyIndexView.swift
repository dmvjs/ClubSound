import SwiftUI

struct KeyIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeKey: MusicKey?
    let selectedBPM: Double?
    let onSelection: (MusicKey) -> Void
    
    // Explicitly track selection state internally
    @State private var selectedKey: MusicKey?
    
    // Fixed width for text and tap target
    private let textWidth: CGFloat = 16
    private let tapTargetWidth: CGFloat = 44
    
    // Add a state variable to force view updates
    @State private var forceRefresh = UUID()
    
    // All possible musical keys
    private let allKeys: [MusicKey] = [.C, .CSharp, .D, .DSharp, .E, .F, .FSharp, .G, .GSharp, .A, .ASharp, .B]
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(allKeys, id: \.self) { key in
                let isSelected = isThisKeySelected(key)
                let isAvailable = availableKeysForSelectedBPM.contains(key)
                
                Text(key.localizedName)
                    .font(.system(size: 11, weight: .semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : (isAvailable ? key.color : Color.gray.opacity(0.5)))
                    .frame(width: textWidth)
                    .frame(maxWidth: tapTargetWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isAvailable {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedKey = key
                                onSelection(key)
                            }
                        }
                    }
                    .accessibilityIdentifier("key-header-\(key.rawValue)")
                    .opacity(isAvailable ? 1.0 : 0.5)
            }
        }
        .frame(width: tapTargetWidth)
        .id(selectedBPM ?? 0) // Force view to recreate when BPM changes
        .onAppear {
            // Initialize with activeKey, but only if it's not already set
            if selectedKey == nil {
                selectedKey = activeKey
            }
        }
        .onChange(of: activeKey) { newValue in
            selectedKey = newValue
        }
        .onChange(of: selectedBPM) { newValue in
            // Force refresh when BPM changes
            forceRefresh = UUID()
            
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
                // Extract all keys from this BPM group and sort them
                let keys = bpmGroup.1.map { $0.0 }.sorted()
                print("Available keys for BPM \(selectedBPM): \(keys)")
                return keys
            }
        }
        
        // If no BPM selected or no matching group, return an empty array
        return []
    }
}

extension MusicKey {
    var color: Color {
        Sample(id: 0, title: "", key: self, bpm: 0, fileName: "").keyColor()
    }
}
