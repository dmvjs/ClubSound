import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var audioManager = AudioManager.shared
    @State private var sampleVolumes: [Int: Float] = [:]
    @State private var nowPlaying: [Sample] = []
    @State private var activeBPM: Double? // Tracks the currently visible BPM
    @StateObject private var wakeLockManager = WakeLockManager()

    @State private var selectedSampleID: Int? // To track the currently selected sample
    @State private var masterVolume: Float = 1.0 // Master volume control

    // Group samples by BPM and Key, sorted by tempo and key
    private var groupedSamples: [(Double, [(Int, [Sample])])] {
        let tempoGroups = Dictionary(grouping: samples) { $0.bpm }.sorted { $0.key < $1.key }
        return tempoGroups.map { (bpm, samples) in
            let keyGroups = Dictionary(grouping: samples) { $0.key }.sorted { $0.key < $1.key }
            return (bpm, keyGroups.map { ($0.key, $0.value.sorted { $0.title < $1.title }) })
        }
    }

    private let minBPM: Double = 60.0
    private let maxBPM: Double = 120.0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        // Tempo Button Row with dynamic safe area padding
                        TempoButtonRow(audioManager: audioManager)
                            .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)

                        // Sample Scroll View
                        SampleScrollView(
                            groupedSamples: groupedSamples,
                            addToNowPlaying: addToNowPlaying,
                            removeFromNowPlaying: removeFromNowPlaying,
                            isInPlaylist: isInPlaylist
                        )

                        // Now Playing View
                        NowPlayingView(
                            proxy: proxy,
                            nowPlaying: $nowPlaying,
                            sampleVolumes: $sampleVolumes,
                            masterVolume: $masterVolume,
                            audioManager: audioManager,
                            removeFromNowPlaying: removeFromNowPlaying
                        )
                    }
                    .background(Color.black)
                    .edgesIgnoringSafeArea(.all)

                    // BPM Index View
                    BPMIndexView(
                        groupedSamples: groupedSamples,
                        activeBPM: activeBPM,
                        onSelection: { bpm in
                            withAnimation {
                                activeBPM = bpm
                                proxy.scrollTo(bpm, anchor: .top)
                            }
                        }
                    )
                    .frame(height: UIScreen.main.bounds.height * 0.5) // Compact height
                    .padding(.top, 50) // Place it 50 points below the TempoButtonRow
                    .padding(.trailing, 20) // Place it 20 points inward from the right edge
                }
                .onAppear {
                    initializeVolumes()
                    selectInitialBPM(proxy: proxy)
                    setupBackgroundAudio()
                }
            }
        }
    }


    private func setupBackgroundAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up background audio: \(error)")
        }
    }

    private func selectInitialBPM(proxy: ScrollViewProxy) {
        if activeBPM == nil {
            activeBPM = 84
        }
    }

    private func initializeVolumes() {
        for sample in samples {
            sampleVolumes[sample.id] = 0.0
        }
    }

    private func addToNowPlaying(sample: Sample) {
        if nowPlaying.count < 4 && !nowPlaying.contains(where: { $0.id == sample.id }) {
            nowPlaying.append(sample)
            sampleVolumes[sample.id] = 0.0
            audioManager.addSampleToPlay(sample)
        }
    }

    private func removeFromNowPlaying(sample: Sample) {
        if let index = nowPlaying.firstIndex(where: { $0.id == sample.id }) {
            withAnimation {
                nowPlaying.remove(at: index)
                audioManager.removeSampleFromPlay(sample)
            }
        }
    }

    private func isInPlaylist(_ sample: Sample) -> Bool {
        nowPlaying.contains(where: { $0.id == sample.id })
    }
}
