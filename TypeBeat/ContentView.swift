import SwiftUI

struct ContentView: View {
    @Bindable var audioManager: AudioManager
    @State private var activeBPM: Double? = 84
    @State private var activeKey: MusicKey? = .C

    private static let maxButtonSize: CGFloat = 44

    /// Samples grouped by BPM then key, both sorted. Derived from the static
    /// catalog so the work happens once per body evaluation regardless of
    /// playback state.
    private var groupedSamples: [(Double, [(MusicKey, [Sample])])] {
        Dictionary(grouping: samples) { $0.bpm }
            .map { bpm, samples in
                let byKey = Dictionary(grouping: samples) { $0.key }
                    .map { ($0.key, $0.value) }
                    .sorted { $0.0.rawValue < $1.0.rawValue }
                return (bpm, byKey)
            }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                ScrollViewReader { proxy in
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: Self.maxButtonSize)

                            SampleScrollView(
                                groupedSamples: groupedSamples,
                                addToNowPlaying: addToNowPlaying,
                                removeFromNowPlaying: removeFromNowPlaying,
                                isInPlaylist: isInPlaylist
                            )
                            .padding(.top, 8)

                            if !audioManager.activeSamples.isEmpty {
                                NowPlayingView(audioManager: audioManager)
                            }
                        }

                        VStack(alignment: .trailing, spacing: 8) {
                            KeyIndexView(
                                groupedSamples: groupedSamples,
                                activeKey: activeKey,
                                selectedBPM: activeBPM,
                                onSelection: { key in handleKeySelection(key, proxy) }
                            )
                            .zIndex(2)

                            BPMIndexView(
                                groupedSamples: groupedSamples,
                                activeBPM: activeBPM,
                                onSelection: { bpm in handleBPMSelection(bpm, proxy) }
                            )
                            .zIndex(2)
                        }
                        .padding(.trailing, 6)
                        .padding(.top, Self.maxButtonSize + 24)

                        HStack {
                            TempoButtonRow(audioManager: audioManager)
                        }
                        .frame(maxWidth: .infinity)
                        .zIndex(2)
                    }
                    .background(Color.black)
                }
            }
        }
    }

    private func addToNowPlaying(sample: Sample) {
        Task { await audioManager.addSampleToPlay(sample) }
    }

    private func removeFromNowPlaying(sample: Sample) {
        withAnimation {
            audioManager.removeSampleFromPlay(sample)
        }
    }

    private func isInPlaylist(_ sample: Sample) -> Bool {
        audioManager.activeSamples.contains { $0.id == sample.id }
    }

    private func handleBPMSelection(_ bpm: Double, _ proxy: ScrollViewProxy) {
        withAnimation {
            activeBPM = bpm
            proxy.scrollTo("\(Int(bpm))", anchor: .top)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func handleKeySelection(_ key: MusicKey, _ proxy: ScrollViewProxy) {
        withAnimation {
            activeKey = key
            if let bpm = activeBPM {
                proxy.scrollTo("\(Int(bpm))-\(key.rawValue)", anchor: .top)
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

#Preview {
    ContentView(audioManager: AudioManager.shared)
}
