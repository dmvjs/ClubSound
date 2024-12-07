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
            return (bpm, keyGroups.map { ($0.key, $0.value.sorted { $0.artist < $1.artist || ($0.artist == $1.artist && $0.title < $1.title) }) })
        }
    }

    private let minBPM: Double = 60.0
    private let maxBPM: Double = 120.0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    VStack(spacing: 0) {
                        TempoButtonRow(audioManager: audioManager)
                        SampleScrollView(proxy: proxy, groupedSamples: groupedSamples, addToNowPlaying: addToNowPlaying, isInPlaylist: isInPlaylist)
                        NowPlayingView(proxy: proxy, nowPlaying: $nowPlaying, sampleVolumes: $sampleVolumes, masterVolume: $masterVolume, audioManager: audioManager, removeFromNowPlaying: removeFromNowPlaying)
                    }
                    .background(Color.black)
                    .edgesIgnoringSafeArea(.all)

                    VStack {
                        BPMIndexView(
                            bpmValues: groupedSamples.map { $0.0 },
                            activeBPM: activeBPM ?? 94,
                            onSelect: { bpm in
                                withAnimation {
                                    proxy.scrollTo(bpm, anchor: .top)
                                    activeBPM = bpm
                                }
                            }
                        )
                        .frame(width: 70)
                        .padding(.trailing, 8)
                        .offset(y: -UIScreen.main.bounds.height * 0.4 + 200)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
            proxy.scrollTo(84, anchor: .top)
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
