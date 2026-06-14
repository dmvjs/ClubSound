import SwiftUI

struct NowPlayingList: View {
    let audioManager: AudioManager

    var body: some View {
        List {
            ForEach(audioManager.activeSamples, id: \.id) { sample in
                NowPlayingRow(
                    sample: sample,
                    volume: Binding(
                        get: { audioManager.volumes[sample.id] ?? 0 },
                        set: { audioManager.setVolume(for: sample, volume: $0) }
                    ),
                    remove: { audioManager.removeSampleFromPlay(sample) },
                    audioManager: audioManager
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("now-playing-row-\(sample.id)")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(audioManager.activeSamples.count) * 60 + 10)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut, value: audioManager.activeSamples.count)
        .accessibilityIdentifier("now-playing-list")
    }
}
