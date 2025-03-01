import SwiftUI

struct BPMIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeBPM: Double?
    let onSelection: (Double) -> Void
    
    // Explicitly track selection state internally
    @State private var selectedBPM: Double?
    
    // Fixed width for text and tap target
    private let textWidth: CGFloat = 24
    private let tapTargetWidth: CGFloat = 44
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(groupedSamples, id: \.0) { bpm, _ in
                let isSelected = isThisBPMSelected(bpm)
                
                Text("\(Int(bpm))")
                    .font(.system(size: 11, weight: .semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                    .frame(width: textWidth)
                    .frame(maxWidth: tapTargetWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            // Force update the selection
                            if selectedBPM == bpm {
                                // If already selected, do nothing
                            } else {
                                selectedBPM = bpm
                                onSelection(bpm)
                            }
                        }
                    }
                    .accessibilityIdentifier("bpm-index-header-\(Int(bpm))")
            }
        }
        .frame(width: tapTargetWidth)
        .onAppear {
            // Initialize with activeBPM, but only if it's not already set
            if selectedBPM == nil {
                selectedBPM = activeBPM
            }
        }
        .onChange(of: activeBPM) { newValue in
            selectedBPM = newValue
        }
    }
    
    // Simplified selection check
    private func isThisBPMSelected(_ bpm: Double) -> Bool {
        if let selected = selectedBPM {
            return abs(selected - bpm) < 0.01
        }
        return false
    }
}

