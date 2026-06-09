import SwiftUI
import AVFoundation

struct ContentView: View {
    let audioManager: AudioManager
    @State private var sampleVolumes: [Int: Float] = [:]
    @State private var nowPlaying: [Sample] = []
    @State private var activeBPM: Double? = 84  // Set initial BPM
    @State private var activeKey: MusicKey? = .C  // Set initial key
    @State private var mainVolume: Float = 0.69

    // Group samples by BPM and Key, sorted by tempo and key
    private var groupedSamples: [(Double, [(MusicKey, [Sample])])] {
        // First, group samples by BPM
        let tempoGroups = Dictionary(grouping: samples) { $0.bpm }
        
        // Convert to array of tuples and sort by BPM
        let sortedTempoGroups = tempoGroups.map { (bpm, samples) -> (Double, [(MusicKey, [Sample])]) in
            // For each BPM group, group samples by key
            let keyGroups = Dictionary(grouping: samples) { $0.key }
            
            // Convert to array of tuples and sort by key
            let sortedKeyGroups = keyGroups.map { (key, samples) -> (MusicKey, [Sample]) in
                return (key, samples)
            }.sorted { $0.0.rawValue < $1.0.rawValue }
            
            return (bpm, sortedKeyGroups)
        }.sorted { $0.0 < $1.0 }

        return sortedTempoGroups
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ZStack(alignment: .topTrailing) {
                        // Base content
                        VStack(spacing: 0) {
                            // Spacer using safe area insets
                            Color.clear
                                .frame(height: maxButtonSize)
                                .padding(.top, 0)

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
                                selectedBPM: activeBPM,
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
                            TempoButtonRow(audioManager: audioManager)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 0)
                        .zIndex(2)
                    }
                    .background(Color.black)
                }
            }
        }
    }

    private func addToNowPlaying(sample: Sample) {
        guard nowPlaying.count < 4,
              !nowPlaying.contains(where: { $0.id == sample.id }) else { return }

        sampleVolumes[sample.id] = 0.0
        nowPlaying.append(sample)

        Task {
            await audioManager.addSampleToPlay(sample)
            audioManager.setVolume(for: sample, volume: 0.0)
        }
    }

    private func removeFromNowPlaying(sample: Sample) {
        withAnimation {
            nowPlaying.removeAll { $0.id == sample.id }
        }
        audioManager.removeSampleFromPlay(sample)
    }

    private func isInPlaylist(_ sample: Sample) -> Bool {
        nowPlaying.contains(where: { $0.id == sample.id })
    }

    private func handleBPMSelection(_ bpm: Double, _ proxy: ScrollViewProxy) {
        // Update the active BPM
        withAnimation {
            activeBPM = bpm
            proxy.scrollTo("\(Int(bpm))", anchor: .top)
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func handleKeySelection(_ key: MusicKey, _ proxy: ScrollViewProxy) {
        withAnimation {
            // Update the active key
            activeKey = key
            
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
