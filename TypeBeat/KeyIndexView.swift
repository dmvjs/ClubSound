import SwiftUI

/// Right-edge key scrubber, modeled on the iOS Contacts A–Z index.
///
/// The whole column lives inside a Liquid Glass capsule so it reads as a
/// single side-affordance, not 12 floating letters. A single DragGesture
/// (minimumDistance 0) both handles taps and lets the user drag a finger
/// up/down to scrub through keys — each new key under the finger fires a
/// light haptic tick and bumps horizontally to flag itself.
struct KeyIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeKey: MusicKey?
    let selectedBPM: Double?
    let onSelection: (MusicKey) -> Void

    @State private var scrubbingKey: MusicKey?

    private let textWidth: CGFloat = 16
    private let tapTargetWidth: CGFloat = 44
    private let rowHeight: CGFloat = 20
    private let rowSpacing: CGFloat = 2
    private let verticalPadding: CGFloat = 8

    private var totalContentHeight: CGFloat {
        let rows = CGFloat(MusicKey.allCases.count)
        return rows * rowHeight + (rows - 1) * rowSpacing + verticalPadding * 2
    }

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(MusicKey.allCases, id: \.self) { key in
                let isAvailable = availableKeys.contains(key)
                let isSelected = activeKey == key
                let isScrubbing = scrubbingKey == key

                Text(key.localizedName)
                    .font(.system(size: 11, weight: .semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : (isAvailable ? key.color : .gray.opacity(0.5)))
                    .frame(width: textWidth)
                    .frame(maxWidth: tapTargetWidth, minHeight: rowHeight, maxHeight: rowHeight)
                    .scaleEffect(
                        x: isScrubbing ? 1.7 : 1.0,
                        y: isScrubbing ? 1.3 : 1.0,
                        anchor: .trailing
                    )
                    .opacity(isAvailable ? 1.0 : 0.5)
                    .accessibilityIdentifier("key-header-\(key.rawValue)")
            }
        }
        .padding(.vertical, verticalPadding)
        .frame(width: tapTargetWidth, height: totalContentHeight)
        .contentShape(Capsule())
        .glassBackground(cornerRadius: tapTargetWidth / 2)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: scrubbingKey)
        .gesture(scrubGesture)
        .onChange(of: selectedBPM) { _, _ in
            // If the previously-selected key isn't available at the new BPM,
            // jump to the first one that is.
            if let activeKey, !availableKeys.contains(activeKey),
               let firstAvailable = availableKeys.first {
                onSelection(firstAvailable)
            }
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let key = keyAtY(value.location.y)
                guard scrubbingKey != key else { return }
                scrubbingKey = key
                if let key, availableKeys.contains(key) {
                    UIImpactFeedbackGenerator(style: .light)
                        .impactOccurred(intensity: 0.55)
                    onSelection(key)
                }
            }
            .onEnded { _ in
                scrubbingKey = nil
            }
    }

    /// Maps a touch Y coordinate (in the column's local frame) to a key
    /// based on the deterministic row layout.
    private func keyAtY(_ y: CGFloat) -> MusicKey? {
        let adjusted = y - verticalPadding
        let rowPitch = rowHeight + rowSpacing
        let index = Int(adjusted / rowPitch)
        let clamped = max(0, min(index, MusicKey.allCases.count - 1))
        return MusicKey.allCases[clamped]
    }

    /// Keys that have at least one sample at the currently-selected BPM.
    private var availableKeys: [MusicKey] {
        guard let selectedBPM,
              let bpmGroup = groupedSamples.first(where: { abs($0.0 - selectedBPM) < 0.01 })
        else { return [] }
        return bpmGroup.1.map(\.0).sorted()
    }
}
