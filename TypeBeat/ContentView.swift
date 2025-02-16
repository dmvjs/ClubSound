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
                    // Base content
                    VStack(spacing: 0) {
                        // Just a spacer for the top row's height
                        Color.clear
                            .frame(height: maxButtonSize)
                            .padding(.top, UIDevice.current.userInterfaceIdiom == .phone ? 0 : (UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0))

                        // Rest of content
                        SampleScrollView(
                            groupedSamples: groupedSamples,
                            addToNowPlaying: addToNowPlaying,
                            removeFromNowPlaying: removeFromNowPlaying,
                            isInPlaylist: isInPlaylist
                        )
                        .padding(.top, 8)

                        if !nowPlaying.isEmpty {
                            NowPlayingView(
                                nowPlaying: $nowPlaying,
                                sampleVolumes: $sampleVolumes,
                                mainVolume: $mainVolume,
                                audioManager: audioManager,
                                removeFromNowPlaying: removeFromNowPlaying
                            )
                        }
                    }

                    // Column buttons
                    VStack(alignment: .trailing, spacing: 8) {
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

                        BPMIndexView(
                            groupedSamples: groupedSamples,
                            activeBPM: activeBPM,
                            onSelection: { bpm in
                                handleBPMSelection(bpm, proxy)
                            }
                        )
                        .allowsHitTesting(true)
                        .zIndex(2)
                    }
                    .padding(.trailing, 6)
                    .padding(.top, maxButtonSize + 24)

                    // Top button row - now at ZStack level
                    HStack {
                        Spacer()
                        TempoButtonRow(audioManager: audioManager)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, UIDevice.current.userInterfaceIdiom == .phone ? 0 : (UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0))
                    .zIndex(2)
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
            // UI updates first
            DispatchQueue.main.async {
                self.nowPlaying.append(sample)
                self.sampleVolumes[sample.id] = 0.0
            }
            
            // Then audio setup
            audioManager.addSampleToPlay(sample)
            
            // Force UI refresh
            DispatchQueue.main.async {
                self.audioManager.objectWillChange.send()
            }
        }
    }

    private func removeFromNowPlaying(sample: Sample) {
        if let index = nowPlaying.firstIndex(where: { $0.id == sample.id }) {
            // UI updates on main thread
            DispatchQueue.main.async {
                withAnimation {
                    // Use Array's remove method explicitly
                    var updatedArray = self.nowPlaying
                    updatedArray.remove(at: index)
                    self.nowPlaying = updatedArray
                }
            }
            
            // Audio cleanup on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                self.audioManager.removeSampleFromPlay(sample)
                // Force UI update on main thread after cleanup
                DispatchQueue.main.async {
                    self.audioManager.objectWillChange.send()
                }
            }
        }
    }

    private func isInPlaylist(_ sample: Sample) -> Bool {
        nowPlaying.contains(where: { $0.id == sample.id })
    }

    func loopProgress() -> Double {
        audioManager.loopProgress()
    }

    private func handleBPMSelection(_ bpm: Double, _ proxy: ScrollViewProxy) {
        // Only scroll, don't change BPM
        withAnimation {
            proxy.scrollTo("\(Int(bpm))", anchor: .top)
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func handleKeySelection(_ key: MusicKey, _ proxy: ScrollViewProxy) {
        withAnimation {
            // Only scroll if we have an active BPM
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
