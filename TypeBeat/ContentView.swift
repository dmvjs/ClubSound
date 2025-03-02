import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var sampleVolumes: [Int: Float] = [:]
    @State private var nowPlaying: [Sample] = []
    @State private var activeBPM: Double? = nil  // Changed from fixed value to nil
    @State private var activeKey: MusicKey? = nil  // Changed from fixed value to nil
    @StateObject private var wakeLockManager = WakeLockManager()
    @State private var mainVolume: Float = 0.69
    @State private var isTransitioning: Bool = false
    @State private var progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

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
            GeometryReader { geometry in
                let safeAreaInsets = geometry.safeAreaInsets
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
        .onAppear {
            // Randomly select initial key and tempo
            selectRandomKeyAndTempo()
            
            // Then load random samples with the selected key
            loadRandomSamples()
        }
        .onReceive(progressTimer) { _ in
            Task {
                await checkLoopProgress()
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
            // Set initial volume to zero
            sampleVolumes[sample.id] = 0.0
            
            // Add to UI first
            DispatchQueue.main.async {
                self.nowPlaying.append(sample)
            }
            
            // Handle audio setup on background thread
            Task.detached(priority: .userInitiated) {
                // Add the new sample without affecting playback
                await self.audioManager.addSampleToPlay(sample)
                
                // Set volume on main thread
                await MainActor.run {
                    self.audioManager.setVolume(for: sample, volume: 0.0)
                    self.audioManager.objectWillChange.send()
                }
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

    /**
     * Selects a random key and tempo for initial app state.
     * This provides variety each time the app is launched.
     */
    private func selectRandomKeyAndTempo() {
        // Get all available keys and tempos from samples
        let allKeys = Set(samples.map { $0.key })
        let allTempos = Set(samples.map { $0.bpm })
        
        // Select random key and tempo if available
        if let randomKey = allKeys.randomElement() {
            activeKey = randomKey
        } else {
            // Fallback to C if no samples available
            activeKey = .C
        }
        
        // Select a random tempo from common values or from available samples
        let commonTempos = [69.0, 84.0, 94.0, 102.0, 120.0, 128.0]
        
        if !allTempos.isEmpty {
            // Prefer to use a tempo from actual samples
            activeBPM = allTempos.randomElement()
        } else if !commonTempos.isEmpty {
            // Fallback to common tempos
            activeBPM = commonTempos.randomElement()
        } else {
            // Ultimate fallback
            activeBPM = 84.0
        }
        
        // Update the audio manager with the selected tempo
        if let tempo = activeBPM {
            audioManager.updateBPM(to: tempo)
        }
    }
    
    /**
     * Loads two random samples of the selected key.
     * This populates the initial playback queue.
     */
    private func loadRandomSamples() {
        guard let currentKey = activeKey else { return }
        
        // Get samples matching the selected key
        let samplesInKey = samples.filter { $0.key == currentKey }
        
        // If we have at least 2 samples in this key
        if samplesInKey.count >= 2 {
            // Get two random samples
            var shuffledSamples = samplesInKey.shuffled()
            if shuffledSamples.count > 2 {
                shuffledSamples = Array(shuffledSamples.prefix(2))
            }
            
            // Add the samples to nowPlaying
            for sample in shuffledSamples {
                addToNowPlaying(sample: sample)
            }
        } else if !samplesInKey.isEmpty {
            // If we have only one sample in this key, use it
            addToNowPlaying(sample: samplesInKey[0])
        } else {
            // If no samples in the selected key, try a different key
            activeKey = MusicKey.allCases.randomElement()
            loadRandomSamples() // Try again with new key
        }
    }

    /**
     * Gets the next key in the circle of fifths progression.
     * If no samples are available in the next key, it will try subsequent keys.
     * 
     * @param currentKey The current key
     * @return The next key with available samples
     */
    private func getNextKeyWithSamples(from currentKey: MusicKey) -> MusicKey? {
        // Start with the next key in the circle of fifths
        var nextKey = getNextKey(from: currentKey)
        
        // Try up to 12 keys (full circle) to find one with samples
        for _ in 0..<12 {
            guard let key = nextKey else { return nil }
            
            // Check if there are samples in this key
            let samplesInKey = samples.filter { $0.key == key }
            if !samplesInKey.isEmpty {
                print("Found \(samplesInKey.count) samples in key \(key)")
                return key
            }
            
            print("No samples in key \(key), trying next key")
            nextKey = getNextKey(from: key)
            
            // If we've gone full circle, break to avoid infinite loop
            if nextKey == currentKey {
                break
            }
        }
        
        // If we couldn't find any key with samples, return nil
        return nil
    }

    /**
     * Checks the loop progress and handles key transitions when approaching the end of a loop.
     * This creates a smooth crossfade between keys at the loop boundary.
     */
    private func checkLoopProgress() async {
        // Only check if we're playing and not already transitioning
        guard audioManager.isPlaying, !isTransitioning, !nowPlaying.isEmpty else { return }
        
        let progress = audioManager.loopProgress()
        
        // Debug print to verify progress is being checked
        if progress > 0.85 {
            print("Loop progress: \(progress)")
        }
        
        // When we reach 90% of the loop
        if progress > 0.9 && !isTransitioning {
            print("Starting transition at progress: \(progress)")
            isTransitioning = true
            
            // Determine the next key with available samples
            guard let currentKey = activeKey, let nextKey = getNextKeyWithSamples(from: currentKey) else {
                print("Failed to find any key with samples")
                isTransitioning = false
                return
            }
            
            print("Transitioning from key \(currentKey) to \(nextKey)")
            
            // Store current samples to fade out
            let currentSamples = nowPlaying
            print("Current samples: \(currentSamples.map { $0.title })")
            
            // Get samples matching the next key
            let samplesInKey = samples.filter { $0.key == nextKey }
            print("Found \(samplesInKey.count) samples in key \(nextKey)")
            
            // Get one or two random samples
            var nextSamples: [Sample] = []
            if samplesInKey.count >= 2 {
                let shuffled = samplesInKey.shuffled()
                nextSamples = Array(shuffled.prefix(2))
            } else {
                nextSamples = [samplesInKey[0]]
            }
            
            print("Selected next samples: \(nextSamples.map { $0.title })")
            
            // Update the active key on main thread
            await MainActor.run {
                activeKey = nextKey
                print("Updated active key to \(nextKey)")
            }
            
            // CRITICAL: Add a significant delay before any audio operations
            print("Waiting before adding new samples...")
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Add samples one at a time with significant delays between
            for (index, sample) in nextSamples.enumerated() {
                print("Adding sample \(index + 1)/\(nextSamples.count): \(sample.title)")
                
                // Set initial volume to zero
                sampleVolumes[sample.id] = 0.0
                
                // Add to UI on main thread
                await MainActor.run {
                    print("Adding \(sample.title) to UI")
                    nowPlaying.append(sample)
                }
                
                // CRITICAL: Add a significant delay after UI update
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Load audio on background thread
                print("Loading audio for \(sample.title)")
                Task {
                    do {
                        await audioManager.addSampleToPlay(sample)
                        print("Successfully loaded audio for \(sample.title)")
                        
                        // Set volume to zero
                        await MainActor.run {
                            audioManager.setVolume(for: sample, volume: 0.0)
                            print("Set initial volume to 0 for \(sample.title)")
                        }
                    } catch {
                        print("Error loading audio for \(sample.title): \(error)")
                    }
                }
                
                // CRITICAL: Add another delay after audio operations
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            print("Starting crossfade...")
            
            // Perform crossfade with fewer steps to reduce CPU load
            let fadeSteps = 10 // Reduced from 30
            for step in 1...fadeSteps {
                let fadeOutRatio = 1.0 - Double(step) / Double(fadeSteps)
                let fadeInRatio = Double(step) / Double(fadeSteps)
                
                if step == 1 || step == fadeSteps {
                    print("Fade step \(step)/\(fadeSteps): out=\(fadeOutRatio), in=\(fadeInRatio)")
                }
                
                // Fade out old samples
                for sample in currentSamples {
                    let originalVolume = sampleVolumes[sample.id] ?? 0.5
                    let newVolume = Float(fadeOutRatio) * originalVolume
                    sampleVolumes[sample.id] = newVolume
                    audioManager.setVolume(for: sample, volume: newVolume)
                }
                
                // Fade in new samples
                for sample in nextSamples {
                    let targetVolume: Float = 0.5
                    let newVolume = Float(fadeInRatio) * targetVolume
                    sampleVolumes[sample.id] = newVolume
                    audioManager.setVolume(for: sample, volume: newVolume)
                }
                
                // Wait longer between fade steps
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            }
            
            print("Crossfade complete, waiting before removing old samples...")
            
            // Wait a full second before removing old samples
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Remove old samples one at a time with significant delays
            for (index, sample) in currentSamples.enumerated() {
                print("Removing old sample \(index + 1)/\(currentSamples.count): \(sample.title)")
                
                // Remove from UI first
                if let index = nowPlaying.firstIndex(where: { $0.id == sample.id }) {
                    await MainActor.run {
                        print("Removing \(sample.title) from UI")
                        nowPlaying.remove(at: index)
                    }
                }
                
                // Wait after UI update
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Then clean up audio
                print("Cleaning up audio for \(sample.title)")
                Task {
                    audioManager.removeSampleFromPlay(sample)
                    print("Successfully removed audio for \(sample.title)")
                }
                
                // Wait after audio cleanup
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            // Reset transition state
            await MainActor.run {
                print("Resetting transition state")
                isTransitioning = false
            }
            
            print("Transition completed to key: \(nextKey)")
        }
    }

    /**
     * Gets the next key in the circle of fifths progression.
     * 
     * @param currentKey The current key
     * @return The next key in the progression
     */
    private func getNextKey(from currentKey: MusicKey) -> MusicKey? {
        switch currentKey {
        case .C: return .G
        case .G: return .D
        case .D: return .A
        case .A: return .E
        case .E: return .B
        case .B: return .FSharp
        case .FSharp: return .CSharp
        case .CSharp: return .GSharp
        case .GSharp: return .DSharp
        case .DSharp: return .ASharp
        case .ASharp: return .F
        case .F: return .C
        }
    }
}

#Preview {
    ContentView(audioManager: AudioManager.shared)
}
