import SwiftUI

struct ContentView: View {
    @Bindable var audioManager: AudioManager
    /// Browse focus once playback has started. While stopped, the scrubber
    /// reads from `audioManager.bpm` directly (see `browseBPM`) so picking a
    /// section is equivalent to choosing the tempo for the next play.
    @State private var activeBPM: Double = 84
    @State private var activeKey: MusicKey? = .C

    private static let maxButtonSize: CGFloat = 44

    /// BPM that the right-edge index, key column, and scroll anchors track.
    /// Locked to `audioManager.bpm` until playback starts — so scrubbing /
    /// tapping a tempo also sets the tempo. Once `isPlaying` flips on it
    /// holds an independent browse focus, letting the user navigate the
    /// catalog without retuning live samples.
    private var browseBPM: Double {
        audioManager.isPlaying ? activeBPM : audioManager.bpm
    }

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
                                selectedBPM: browseBPM,
                                onSelection: { key in handleKeySelection(key, proxy) }
                            )
                            .zIndex(2)

                            BPMIndexView(
                                groupedSamples: groupedSamples,
                                activeBPM: browseBPM,
                                onSelection: { bpm in handleBPMSelection(bpm, proxy) }
                            )
                            .zIndex(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.trailing, 6)
                        // Reserve the bottom area occupied by the now-playing
                        // strip + control row, then center the scrubber columns
                        // in the remaining space above it.
                        .padding(.bottom, bottomReserveForScrubbers)
                    }
                    .background(Color.black)
                    // While stopped, any BPM change (tempo button or scrubber)
                    // also scrolls the list — `browseBPM` already follows
                    // `audioManager.bpm` for the highlight, so this only owns
                    // the imperative scroll.
                    .onChange(of: audioManager.bpm) { _, newBPM in
                        guard !audioManager.isPlaying,
                              groupedSamples.contains(where: { abs($0.0 - newBPM) < 0.01 })
                        else { return }
                        withAnimation {
                            proxy.scrollTo("\(Int(newBPM))", anchor: .top)
                        }
                    }
                    // Seed the browse focus from the playback tempo at the
                    // moment play starts, so the scrubber doesn't jump to a
                    // stale value when the modes flip.
                    .onChange(of: audioManager.isPlaying) { _, nowPlaying in
                        if nowPlaying { activeBPM = audioManager.bpm }
                    }
                }
            }
        }
    }

    private func addToNowPlaying(sample: Sample) {
        // Manual pick implicitly drops out of auto — the user taking the
        // wheel is a clear signal they don't want the scheduler fighting
        // them — but the pick itself still goes through.
        if audioManager.autoDJ.isEnabled { audioManager.autoDJ.isEnabled = false }
        Task { await audioManager.addSampleToPlay(sample) }
    }

    private func removeFromNowPlaying(sample: Sample) {
        if audioManager.autoDJ.isEnabled { audioManager.autoDJ.isEnabled = false }
        withAnimation {
            audioManager.removeSampleFromPlay(sample)
        }
    }

    private func isInPlaylist(_ sample: Sample) -> Bool {
        audioManager.activeSamples.contains { $0.id == sample.id }
    }

    /// Height to reserve at the bottom of the scrubber column so it sits
    /// just above the master-volume tab instead of overlapping the
    /// now-playing strip. Scales with how many songs are loaded.
    private var bottomReserveForScrubbers: CGFloat {
        let controlRow: CGFloat = 64
        let mainVolume: CGFloat = audioManager.activeSamples.isEmpty ? 0 : 56
        let perSongRow: CGFloat = 56
        let songRows = CGFloat(audioManager.activeSamples.count) * perSongRow
        let buffer: CGFloat = 28
        return controlRow + mainVolume + songRows + buffer
    }

    private func handleBPMSelection(_ bpm: Double, _ proxy: ScrollViewProxy) {
        if audioManager.isPlaying {
            activeBPM = bpm
            withAnimation { proxy.scrollTo("\(Int(bpm))", anchor: .top) }
        } else {
            // Drives the highlight (via `browseBPM`) and the scroll (via the
            // onChange above) in one assignment.
            audioManager.bpm = bpm
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func handleKeySelection(_ key: MusicKey, _ proxy: ScrollViewProxy) {
        withAnimation {
            activeKey = key
            proxy.scrollTo("\(Int(browseBPM))-\(key.rawValue)", anchor: .top)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

#Preview {
    ContentView(audioManager: AudioManager.shared)
}


