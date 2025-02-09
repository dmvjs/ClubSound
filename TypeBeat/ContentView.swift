import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var sampleVolumes: [Int: Float] = [:]
    @State private var nowPlaying: [Sample] = []
    @State private var activeBPM: Double? = 84  // Set initial BPM
    @State private var activeKey: MusicKey? = .C  // Set initial key
    @StateObject private var wakeLockManager = WakeLockManager()
    @State private var mainVolume: Float = 0.69

    // Group samples by BPM and Key, sorted by tempo and key
    private var groupedSamples: [(Double, [(MusicKey, [Sample])])] {
        let tempoGroups = Dictionary(grouping: samples) { $0.bpm }.sorted { $0.key < $1.key }
        return tempoGroups.map { (bpm, samples) in
            let keyGroups = Dictionary(grouping: samples) { $0.key }.sorted { $0.key.rawValue < $1.key.rawValue }
            return (bpm, keyGroups)
        }
    }

    private let minBPM: Double = 60.0
    private let maxBPM: Double = 120.0
    private let keyColumnWidth: CGFloat = 48  // Width of key column + padding

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        // Tempo Button Row at top
                        HStack {
                            Spacer()
                            TempoButtonRow(audioManager: audioManager)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)
                        .padding(.trailing, keyColumnWidth)  // Account for key column width

                        // Sample list below
                        SampleScrollView(
                            groupedSamples: groupedSamples,
                            addToNowPlaying: addToNowPlaying,
                            removeFromNowPlaying: removeFromNowPlaying,
                            isInPlaylist: isInPlaylist
                        )
                        .padding(.top, 8)
                        
                        if !audioManager.activeSamples.isEmpty {
                            NowPlayingView(
                                nowPlaying: $nowPlaying,
                                sampleVolumes: $sampleVolumes,
                                mainVolume: $mainVolume,
                                audioManager: audioManager,
                                removeFromNowPlaying: removeFromNowPlaying
                            )
                        }
                    }

                    // Fixed-height BPM and Key columns
                    HStack(alignment: .top, spacing: 0) {
                        BPMIndexView(
                            groupedSamples: groupedSamples,
                            activeBPM: activeBPM,
                            onSelection: { bpm in
                                activeBPM = bpm
                                if let key = activeKey {
                                    let scrollID = "\(Int(bpm))-\(key.rawValue)"
                                    withAnimation {
                                        proxy.scrollTo(scrollID, anchor: .top)
                                    }
                                } else {
                                    let scrollID = "\(Int(bpm))"
                                    withAnimation {
                                        proxy.scrollTo(scrollID, anchor: .top)
                                    }
                                }
                            }
                        )
                        .frame(height: UIScreen.main.bounds.height * 0.33)
                        .padding(.top, -UIScreen.main.bounds.height * 0.025)
                        
                        KeyIndexView(
                            groupedSamples: groupedSamples,
                            activeKey: activeKey,
                            activeBPM: activeBPM,
                            onSelection: { key in
                                activeKey = key
                                if let bpm = activeBPM {
                                    let scrollID = "\(Int(bpm))-\(key.rawValue)"
                                    withAnimation {
                                        proxy.scrollTo(scrollID, anchor: .top)
                                    }
                                }
                            }
                        )
                        .frame(height: UIScreen.main.bounds.height * 0.33)
                        .frame(width: keyColumnWidth)
                    }
                    .padding(.trailing, 6)
                    .padding(.top, maxButtonSize + 20)
                    .zIndex(1)
                }
                .background(Color.black)
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

    private func selectInitialBPM() {
        if activeBPM == nil {
            activeBPM = 84
        }
    }

    private func initializeVolumes() {
        for sample in samples {
            sampleVolumes[sample.id] = 0.0
        }
        audioManager.setMasterVolume(mainVolume)  // Set initial master volume
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

    func loopProgress(for sampleId: Int) -> Double {
        audioManager.loopProgress(for: sampleId)
    }

    private func handleBPMSelection(_ bpm: Double) {
        activeBPM = bpm
        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    private func handleKeySelection(_ key: MusicKey) {
        activeKey = key
        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private let maxButtonSize: CGFloat = 44
}

#Preview {
    ContentView(audioManager: AudioManager.shared)
}
