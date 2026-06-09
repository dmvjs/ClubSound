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
            GeometryReader { geometry in
                let safeTop = geometry.safeAreaInsets.top
                ScrollViewReader { proxy in
                    ZStack(alignment: .topTrailing) {
                        SampleScrollView(
                            groupedSamples: groupedSamples,
                            addToNowPlaying: addToNowPlaying,
                            removeFromNowPlaying: removeFromNowPlaying,
                            isInPlaylist: isInPlaylist
                        )
                        .softScrollEdges()
                        // Solid black behind the status bar / Dynamic Island
                        // zone — the BPM header pins right below this.
                        .overlay(alignment: .top) {
                            Color.black
                                .frame(height: safeTop)
                                .ignoresSafeArea(edges: .top)
                                .allowsHitTesting(false)
                        }
                        // Soft fade right below the pinned BPM header (header
                        // height = 44pt) so song titles dissolve before they
                        // collide with the header text above.
                        .overlay(alignment: .top) {
                            LinearGradient(
                                colors: [Color.black, Color.black.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 40)
                            .padding(.top, 44)
                            .allowsHitTesting(false)
                        }
                        // Symmetric fade at the bottom of the scroll area,
                        // above the now-playing strip.
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [Color.black.opacity(0), Color.black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 60)
                            .allowsHitTesting(false)
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            // Bottom-anchored UI, stacked thumb-first:
                            //   1. Now-playing strip (volume sliders) —
                            //      transparent so the glass tabs can sample
                            //      the scroll-list content above them
                            //   2. Primary controls (play, tempos, etc.) on a
                            //      solid black backdrop so the bottom row
                            //      reads as a dock
                            //
                            // GlassGroup wraps both so iOS 26's glassEffect
                            // children initialize their backdrop sampling
                            // correctly on first composite (without it, the
                            // tabs flash white until a state change forces a
                            // re-layout).
                            GlassGroup {
                                VStack(spacing: 0) {
                                    if !audioManager.activeSamples.isEmpty {
                                        NowPlayingView(audioManager: audioManager)
                                    }
                                    TempoButtonRow(audioManager: audioManager)
                                        .padding(.bottom, 4)
                                }
                                .background(Color.black)
                            }
                        }

                        VStack(alignment: .trailing, spacing: 8) {
                            Spacer(minLength: 0)
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
                            Spacer(minLength: 0)
                        }
                        .padding(.trailing, 6)
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
