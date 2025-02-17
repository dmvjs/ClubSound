import SwiftUI

struct BPMIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeBPM: Double?
    let onSelection: (Double) -> Void
    
    @State private var selectedBPM: Double?
    @State private var showingIndicator = false
    
    // Fixed width for text and tap target
    private let textWidth: CGFloat = 24
    private let tapTargetWidth: CGFloat = 44
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(groupedSamples, id: \.0) { bpm, _ in
                Text("\(Int(bpm))")
                    .font(.system(size: 11, weight: .semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundColor(activeBPM == bpm ? .white : .white.opacity(0.5))
                    .frame(width: textWidth)
                    .frame(maxWidth: tapTargetWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onSelection(bpm)
                        }
                    }
                    .accessibilityIdentifier("bpm-index-header-\(Int(bpm))")
            }
        }
        .frame(width: tapTargetWidth)
    }
}

