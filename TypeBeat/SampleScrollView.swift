import SwiftUI

struct SampleScrollView: View {
    let groupedSamples: [(Double, [(Int, [Sample])])]
    let addToNowPlaying: (Sample) -> Void
    let isInPlaylist: (Sample) -> Bool
    @State private var activeBPM: Double? = nil // Track the active BPM

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                VStack(spacing: 0) {
                    // Main Scrollable Content
                    ScrollView {
                        VStack(spacing: 20) {
                            ForEach(groupedSamples, id: \.0) { (bpm, keyGroups) in
                                VStack(alignment: .leading) {
                                    // BPM Header
                                    Text("\(Int(bpm)) BPM")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding(.leading)
                                        .id(bpm)
                                        .background(
                                            GeometryReader { geometry in
                                                Color.clear
                                                    .onChange(of: geometry.frame(in: .global).minY) { _ in
                                                        updateActiveBPM(for: bpm, using: geometry)
                                                    }
                                            }
                                        )

                                    ForEach(keyGroups, id: \.0) { (_, samples) in
                                        VStack(alignment: .leading, spacing: 10) {
                                            // Sample List
                                            ForEach(samples, id: \.id) { sample in
                                                SampleRecordView(
                                                    sample: sample,
                                                    isInPlaylist: isInPlaylist(sample)
                                                ) {
                                                    addToNowPlaying(sample)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 80) // Adjust bottom padding
                    }

                    // Now Playing View
                    NowPlayingView(
                        proxy: scrollProxy,
                        nowPlaying: .constant([]),
                        sampleVolumes: .constant([:]),
                        masterVolume: .constant(1.0),
                        audioManager: AudioManager.shared,
                        removeFromNowPlaying: { _ in }
                    )
                    .padding(.bottom, geometry.safeAreaInsets.bottom) // Align with safe area
                    .background(
                        Color.black.opacity(0.9)
                            .edgesIgnoringSafeArea(.bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: -3)
                }
            }
        }
    }

    private func updateActiveBPM(for bpm: Double, using geometry: GeometryProxy) {
        let frame = geometry.frame(in: .global)
        let screenHeight = UIScreen.main.bounds.height
        let isVisible = frame.minY >= 0 && frame.minY < screenHeight * 0.5
        if isVisible {
            activeBPM = bpm
        }
    }
}
