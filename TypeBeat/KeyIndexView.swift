import SwiftUI

struct KeyIndexView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let activeKey: MusicKey?
    let selectedBPM: Double?
    let onSelection: (MusicKey) -> Void

    private let textWidth: CGFloat = 16
    private let tapTargetWidth: CGFloat = 44

    var body: some View {
        VStack(spacing: 2) {
            ForEach(MusicKey.allCases, id: \.self) { key in
                let isAvailable = availableKeys.contains(key)
                let isSelected = activeKey == key

                Text(key.localizedName)
                    .font(.system(size: 11, weight: .semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : (isAvailable ? key.color : .gray.opacity(0.5)))
                    .frame(width: textWidth)
                    .frame(maxWidth: tapTargetWidth)
                    .contentShape(Rectangle())
                    .opacity(isAvailable ? 1.0 : 0.5)
                    .accessibilityIdentifier("key-header-\(key.rawValue)")
                    .onTapGesture {
                        guard isAvailable else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            onSelection(key)
                        }
                    }
            }
        }
        .frame(width: tapTargetWidth)
        .onChange(of: selectedBPM) { _, _ in
            // If the previously-selected key isn't available at the new BPM,
            // jump to the first one that is.
            if let activeKey, !availableKeys.contains(activeKey),
               let firstAvailable = availableKeys.first {
                onSelection(firstAvailable)
            }
        }
    }

    /// Keys that have at least one sample at the currently-selected BPM.
    private var availableKeys: [MusicKey] {
        guard let selectedBPM,
              let bpmGroup = groupedSamples.first(where: { abs($0.0 - selectedBPM) < 0.01 })
        else { return [] }
        return bpmGroup.1.map(\.0).sorted()
    }
}
