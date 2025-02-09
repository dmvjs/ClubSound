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
                        // Tempo Button Row at top - adjusted padding for Pro Max
                        HStack {
                            Spacer()
                            TempoButtonRow(audioManager: audioManager)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, UIDevice.current.userInterfaceIdiom == .phone ? 0 : UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)
                        .padding(.trailing, keyColumnWidth)

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
                    VStack(alignment: .trailing, spacing: 8) {
                        BPMIndexView(
                            groupedSamples: groupedSamples,
                            activeBPM: activeBPM,
                            onSelection: { bpm in
                                handleBPMSelection(bpm, proxy)
                            }
                        )
                        .allowsHitTesting(true)
                        .zIndex(2)
                        
                        KeyIndexView(
                            groupedSamples: groupedSamples,
                            activeKey: activeKey,
                            activeBPM: activeBPM,
                            onSelection: { key in
                                handleKeySelection(key, proxy)
                            }
                        )
                        .allowsHitTesting(true)
                        .zIndex(2)
                    }
                    .padding(.trailing, 6)
                    .padding(.top, maxButtonSize)
                    .zIndex(2)  // Ensure entire column stack stays above
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
            // UI update on main thread
            nowPlaying.append(sample)
            sampleVolumes[sample.id] = 0.0
            
            // Audio operations on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                audioManager.addSampleToPlay(sample)
                DispatchQueue.main.async {
                    // Force UI update
                    audioManager.objectWillChange.send()
                }
            }
        }
    }

    private func removeFromNowPlaying(sample: Sample) {
        if let index = nowPlaying.firstIndex(where: { $0.id == sample.id }) {
            // UI update on main thread
            withAnimation {
                nowPlaying.remove(at: index)
            }
            
            // Audio operations on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                audioManager.removeSampleFromPlay(sample)
                DispatchQueue.main.async {
                    // Force UI update
                    audioManager.objectWillChange.send()
                }
            }
        }
    }

    private func isInPlaylist(_ sample: Sample) -> Bool {
        nowPlaying.contains(where: { $0.id == sample.id })
    }

    func loopProgress(for sampleId: Int) -> Double {
        audioManager.loopProgress(for: sampleId)
    }

    private func handleBPMSelection(_ bpm: Double, _ proxy: ScrollViewProxy) {
        withAnimation {
            // Update BPM first
            activeBPM = bpm
            
            // If current key exists in new BPM, keep it and scroll there
            let keysForNewBPM = groupedSamples
                .first(where: { $0.0 == bpm })?
                .1
                .map { $0.0 } ?? []
                
            if let currentKey = activeKey, !keysForNewBPM.contains(currentKey) {
                // If current key doesn't exist in new BPM, clear it
                activeKey = nil
            }
            
            // Scroll to BPM section
            proxy.scrollTo("\(Int(bpm))", anchor: .top)
        }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    private func handleKeySelection(_ key: MusicKey, _ proxy: ScrollViewProxy) {
        withAnimation {
            activeKey = key
            
            // If we don't have a BPM selected, find first BPM that has this key
            if activeBPM == nil {
                if let firstBPMWithKey = groupedSamples.first(where: { _, keyGroups in
                    keyGroups.contains { $0.0 == key }
                }) {
                    activeBPM = firstBPMWithKey.0
                }
            }
            
            // Now scroll to the key section if we have a BPM
            if let bpm = activeBPM {
                proxy.scrollTo("\(Int(bpm))-\(key.rawValue)", anchor: .top)
            }
        }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private let maxButtonSize: CGFloat = 44
}

#Preview {
    ContentView(audioManager: AudioManager.shared)
}
