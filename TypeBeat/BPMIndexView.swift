import SwiftUI

/// Right-edge BPM scrubber, matching KeyIndexView's Contacts-style treatment:
/// a Liquid Glass capsule with drag-to-scrub, haptic ticks on every new
/// target, and a horizontal scale bump on the currently-highlighted row.
struct BPMIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeBPM: Double?
    let onSelection: (Double) -> Void

    @State private var scrubbingBPM: Double?

    private let textWidth: CGFloat = 24
    private let tapTargetWidth: CGFloat = 44
    private let rowHeight: CGFloat = 20
    private let rowSpacing: CGFloat = 2
    private let verticalPadding: CGFloat = 8

    private var bpms: [Double] { groupedSamples.map(\.0) }

    private var totalContentHeight: CGFloat {
        let rows = CGFloat(bpms.count)
        return rows * rowHeight + max(0, rows - 1) * rowSpacing + verticalPadding * 2
    }

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(bpms, id: \.self) { bpm in
                let isSelected = activeBPM.map { abs($0 - bpm) < 0.01 } ?? false
                let isScrubbing = scrubbingBPM.map { abs($0 - bpm) < 0.01 } ?? false

                Text("\(Int(bpm))")
                    .font(.system(size: 13, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                    .frame(width: textWidth)
                    .frame(maxWidth: tapTargetWidth, minHeight: rowHeight, maxHeight: rowHeight)
                    .scaleEffect(
                        x: isScrubbing ? 1.6 : 1.0,
                        y: isScrubbing ? 1.3 : 1.0,
                        anchor: .trailing
                    )
                    .accessibilityIdentifier("bpm-index-header-\(Int(bpm))")
            }
        }
        .padding(.vertical, verticalPadding)
        .frame(width: tapTargetWidth, height: totalContentHeight)
        .contentShape(Capsule())
        .glassBackground(cornerRadius: tapTargetWidth / 2)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: scrubbingBPM)
        .gesture(scrubGesture)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let bpm = bpmAtY(value.location.y)
                guard scrubbingBPM != bpm else { return }
                scrubbingBPM = bpm
                if let bpm {
                    UIImpactFeedbackGenerator(style: .light)
                        .impactOccurred(intensity: 0.55)
                    onSelection(bpm)
                }
            }
            .onEnded { _ in
                scrubbingBPM = nil
            }
    }

    /// Maps a touch Y coordinate (in the column's local frame) to a BPM
    /// based on the deterministic row layout.
    private func bpmAtY(_ y: CGFloat) -> Double? {
        let adjusted = y - verticalPadding
        let rowPitch = rowHeight + rowSpacing
        let index = Int(adjusted / rowPitch)
        let clamped = max(0, min(index, bpms.count - 1))
        return bpms.indices.contains(clamped) ? bpms[clamped] : nil
    }
}
