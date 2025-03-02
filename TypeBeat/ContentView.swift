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
    @State private var useRandomSongs: Bool = false
    @State private var songCounter: Int = 0
    @State private var tempoIndex: Int = 0
    @State private var playedSampleIds: Set<Int> = []
    private let tempoOptions: [Double] = [84.0, 94.0, 102.0]
    @State private var lastSelectedTempo: Double? = nil
    @State private var targetBPM: Double? = nil
    @State private var pendingTempoChange = false
    @State private var pendingTempoChangeProgress: CGFloat = 0.0

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
                            TempoButtonRow(
                                audioManager: audioManager,
                                onTempoSelected: { tempo in
                                    print("TEMPO BUTTON CLICKED: \(tempo)")
                                    scheduleTempoChange(tempo)
                                },
                                pendingTempoChange: $pendingTempoChange,
                                pendingTempoChangeProgress: $pendingTempoChangeProgress
                            )
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
            // Enable wake lock on app launch
            wakeLockManager.enableWakeLock()
            
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
        // Select initial tempo from our predefined options
        // Start with a random index
        tempoIndex = Int.random(in: 0..<tempoOptions.count)
        activeBPM = tempoOptions[tempoIndex]
        
        print("Selected initial tempo: \(activeBPM ?? 0) BPM")
        
        // Update the audio manager with the selected tempo
        if let tempo = activeBPM {
            audioManager.updateBPM(to: tempo)
        }
        
        // Find samples matching the selected tempo
        let tempoTolerance = 0.5
        let samplesMatchingTempo = samples.filter { sample in
            guard let tempo = activeBPM else { return false }
            return abs(sample.bpm - tempo) <= tempoTolerance
        }
        
        if samplesMatchingTempo.isEmpty {
            print("No samples match the selected tempo \(activeBPM ?? 0), trying a different tempo")
            // Try a different tempo
            for tempo in tempoOptions {
                let matchingSamples = samples.filter { abs($0.bpm - tempo) <= tempoTolerance }
                if !matchingSamples.isEmpty {
                    activeBPM = tempo
                    audioManager.updateBPM(to: tempo)
                    print("Found matching samples at tempo \(tempo) BPM")
                    break
                }
            }
        }
        
        // Now get all available keys from samples matching the selected tempo
        let samplesForTempo = samples.filter { sample in
            guard let tempo = activeBPM else { return false }
            return abs(sample.bpm - tempo) <= tempoTolerance
        }
        
        let availableKeys = Set(samplesForTempo.map { $0.key })
        
        // Select random key from available keys
        if let randomKey = availableKeys.randomElement() {
            activeKey = randomKey
            print("Selected random key \(randomKey) from available keys for tempo \(activeBPM ?? 0)")
        } else {
            // Fallback to C if no samples available
            activeKey = .C
            print("No keys available for tempo \(activeBPM ?? 0), defaulting to C")
        }
        
        // Reset song counter
        songCounter = 0
        
        print("Initial setup complete: Tempo \(activeBPM ?? 0) BPM, Key \(activeKey?.rawValue ?? "none")")
    }
    
    /**
     * Loads two random samples of the selected key.
     * This populates the initial playback queue with volumes set to 50%.
     */
    private func loadRandomSamples() {
        guard let currentKey = activeKey, let currentTempo = activeBPM else { return }
        
        print("Loading random samples with key: \(currentKey), tempo: \(currentTempo)")
        
        // Get samples matching the selected key AND tempo (with small tolerance)
        let tempoTolerance = 0.5 // Allow 0.5 BPM difference
        let samplesInKeyAndTempo = samples.filter { 
            $0.key == currentKey && abs($0.bpm - currentTempo) <= tempoTolerance 
        }
        
        print("Found \(samplesInKeyAndTempo.count) samples matching key \(currentKey) and tempo \(currentTempo)")
        
        // If we have samples matching both key and tempo
        if !samplesInKeyAndTempo.isEmpty {
            // Get up to two random samples
            var shuffledSamples = samplesInKeyAndTempo.shuffled()
            if shuffledSamples.count > 2 {
                shuffledSamples = Array(shuffledSamples.prefix(2))
            }
            
            // First add all samples to UI
            for sample in shuffledSamples {
                // Set initial volume to 50% (0.5) in the UI
                sampleVolumes[sample.id] = 0.5
                
                // Add to UI
                nowPlaying.append(sample)
                print("Added sample to UI: \(sample.title) (BPM: \(sample.bpm), Key: \(sample.key))")
            }
            
            // Then load and set volumes with a delay to ensure proper initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                for sample in shuffledSamples {
                    // Handle audio setup
                    Task {
                        // Add the sample to play
                        await self.audioManager.addSampleToPlay(sample)
                        
                        // Force volume to 50% with multiple attempts
                        self.audioManager.setVolume(for: sample, volume: 0.5)
                        print("Initial set volume for \(sample.title) to 0.5")
                        
                        // Try again after a short delay
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        self.audioManager.setVolume(for: sample, volume: 0.5)
                        print("Second attempt set volume for \(sample.title) to 0.5")
                        
                        // Notify observers
                        self.audioManager.objectWillChange.send()
                    }
                }
            }
        } else {
            print("No samples match both key and tempo, trying with just tempo")
            // If no samples match both key and tempo, try with just tempo
            let samplesMatchingTempo = samples.filter { abs($0.bpm - currentTempo) <= tempoTolerance }
            
            if !samplesMatchingTempo.isEmpty {
                // Get up to two random samples
                var shuffledSamples = samplesMatchingTempo.shuffled()
                if shuffledSamples.count > 2 {
                    shuffledSamples = Array(shuffledSamples.prefix(2))
                }
                
                // Update the key to match the first sample
                if let firstSample = shuffledSamples.first {
                    activeKey = firstSample.key
                    print("Updated active key to \(firstSample.key) to match available samples")
                }
                
                // First add all samples to UI
                for sample in shuffledSamples {
                    // Set initial volume to 50% (0.5) in the UI
                    sampleVolumes[sample.id] = 0.5
                    
                    // Add to UI
                    nowPlaying.append(sample)
                    print("Added sample to UI: \(sample.title) (BPM: \(sample.bpm), Key: \(sample.key))")
                }
                
                // Then load and set volumes with a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    for sample in shuffledSamples {
                        // Handle audio setup
                        Task {
                            // Add the sample to play
                            await self.audioManager.addSampleToPlay(sample)
                            
                            // Force volume to 50% with multiple attempts
                            self.audioManager.setVolume(for: sample, volume: 0.5)
                            print("Initial set volume for \(sample.title) to 0.5")
                            
                            // Try again after a short delay
                            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                            self.audioManager.setVolume(for: sample, volume: 0.5)
                            print("Second attempt set volume for \(sample.title) to 0.5")
                            
                            // Notify observers
                            self.audioManager.objectWillChange.send()
                        }
                    }
                }
            } else {
                // If no samples match the tempo at all, try a different tempo
                print("No samples match the selected tempo at all, trying a different tempo")
                for tempo in tempoOptions {
                    if tempo != currentTempo {
                        let matchingSamples = samples.filter { abs($0.bpm - tempo) <= tempoTolerance }
                        if !matchingSamples.isEmpty {
                            // Update tempo
                            activeBPM = tempo
                            audioManager.updateBPM(to: tempo)
                            print("Switching to tempo \(tempo) BPM which has matching samples")
                            
                            // Try loading samples again with the new tempo
                            loadRandomSamples()
                            return
                        }
                    }
                }
            }
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
     * Modified checkLoopProgress to handle pending tempo changes with hard cuts.
     * Incorporates the robust loading approach from the original code.
     */
    private func checkLoopProgress() async {
        // Only check if we're playing and not already transitioning
        guard audioManager.isPlaying, !isTransitioning, !nowPlaying.isEmpty else { return }
        
        let progress = audioManager.loopProgress()
        
        // When we reach 90% of the loop
        if progress > 0.9 && !isTransitioning {
            print("Starting transition at progress: \(progress)")
            isTransitioning = true
            
            // Check if we have a pending tempo change
            if pendingTempoChange, let newTempo = targetBPM {
                print("Applying pending tempo change to \(newTempo) BPM")
                
                // Store current samples to fade out
                let currentSamples = nowPlaying
                print("Current samples: \(currentSamples.map { $0.title })")
                
                // Wait until we're very close to the loop end
                while audioManager.loopProgress() < 0.99 {
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
                
                print("Performing tempo change at loop boundary")
                
                // Update audio manager with new tempo
                audioManager.updateBPM(to: newTempo)
                
                // Reset pending flag
                pendingTempoChange = false
                targetBPM = nil
                
                // Get samples matching the new tempo (with a small tolerance)
                let tempoTolerance = 0.5 // Allow 0.5 BPM difference
                let samplesMatchingTempo = samples.filter { 
                    abs($0.bpm - newTempo) <= tempoTolerance 
                }
                
                if samplesMatchingTempo.isEmpty {
                    print("No samples found matching tempo \(newTempo)")
                    isTransitioning = false
                    return
                }
                
                print("Found \(samplesMatchingTempo.count) samples matching tempo \(newTempo)")
                
                // Pick a random key with samples at this tempo
                let keysWithSamples = Set(samplesMatchingTempo.map { $0.key })
                guard let randomKey = keysWithSamples.randomElement() else {
                    print("No keys with samples at tempo \(newTempo)")
                    isTransitioning = false
                    return
                }
                
                // Update key
                await MainActor.run {
                    activeKey = randomKey
                }
                print("Selected key \(randomKey) for tempo \(newTempo)")
                
                // Pick two random samples
                let shuffled = samplesMatchingTempo.shuffled()
                var selectedSamples: [Sample] = []
                
                if shuffled.count >= 2 {
                    selectedSamples = Array(shuffled.prefix(2))
                } else if !shuffled.isEmpty {
                    selectedSamples = [shuffled[0]]
                }
                
                if selectedSamples.isEmpty {
                    print("Failed to select samples")
                    isTransitioning = false
                    return
                }
                
                print("Selected \(selectedSamples.count) samples: \(selectedSamples.map { $0.title })")
                
                // CRITICAL: Add a significant delay before any audio operations
                print("Waiting before adding new samples...")
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // First, mute old samples
                for sample in currentSamples {
                    audioManager.setVolume(for: sample, volume: 0.0)
                }
                
                // Add new samples to UI first
                for (index, sample) in selectedSamples.enumerated() {
                    print("Adding sample \(index + 1)/\(selectedSamples.count): \(sample.title)")
                    
                    // Set initial volume to zero in the UI
                    sampleVolumes[sample.id] = 0.0
                    
                    // Add to UI on main thread
                    await MainActor.run {
                        print("Adding \(sample.title) to UI")
                        nowPlaying.append(sample)
                    }
                    
                    // CRITICAL: Add a significant delay after UI update
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
                
                // Then load audio for new samples
                for sample in selectedSamples {
                    print("Loading audio for \(sample.title)")
                    do {
                        await audioManager.addSampleToPlay(sample)
                        print("Successfully loaded audio for \(sample.title)")
                        
                        // Set volume to 50% with multiple attempts
                        audioManager.setVolume(for: sample, volume: 0.5)
                        print("Initial set volume for \(sample.title) to 0.5")
                        
                        // Try again after a short delay
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        audioManager.setVolume(for: sample, volume: 0.5)
                        print("Second attempt set volume for \(sample.title) to 0.5")
                        
                        // Update UI volume
                        sampleVolumes[sample.id] = 0.5
                        
                        // Notify observers
                        audioManager.objectWillChange.send()
                    } catch {
                        print("Error loading audio for \(sample.title): \(error)")
                    }
                    
                    // CRITICAL: Add another delay after audio operations
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
                
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
                
                print("Tempo change transition completed to key: \(randomKey)")
                return
            }
            
            // For regular transitions, continue with normal logic
            // ... rest of the regular transition code ...
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

    /**
     * Gets the next key in the circle of fifths progression that matches the given tempo.
     * Prioritizes keys with unplayed samples.
     * 
     * @param currentKey The current key
     * @param tempo The target tempo
     * @param playedIds Set of sample IDs that have already been played
     * @return The next key in the progression that matches the given tempo
     */
    private func getNextKeyWithSamplesMatchingTempo(from currentKey: MusicKey, tempo: Double, playedIds: Set<Int>) -> MusicKey? {
        // Start with the next key in the circle of fifths
        var nextKey = getNextKey(from: currentKey)
        
        // Try up to 12 keys (full circle) to find one with unplayed samples matching the given tempo
        for _ in 0..<12 {
            guard let key = nextKey else { return nil }
            
            // Check if there are unplayed samples in this key matching the given tempo
            let samplesInKey = samples.filter { 
                $0.key == key && abs($0.bpm - tempo) <= 0.5 && !playedIds.contains($0.id)
            }
            
            if !samplesInKey.isEmpty {
                print("Found \(samplesInKey.count) unplayed samples in key \(key) matching tempo \(tempo)")
                return key
            }
            
            nextKey = getNextKey(from: key)
            
            // If we've gone full circle, break to avoid infinite loop
            if nextKey == currentKey {
                break
            }
        }
        
        // If we couldn't find any key with unplayed samples, try again allowing played samples
        nextKey = getNextKey(from: currentKey)
        
        for _ in 0..<12 {
            guard let key = nextKey else { return nil }
            
            // Check if there are any samples in this key matching the given tempo
            let samplesInKey = samples.filter { 
                $0.key == key && abs($0.bpm - tempo) <= 0.5
            }
            
            if !samplesInKey.isEmpty {
                print("Found \(samplesInKey.count) samples in key \(key) matching tempo \(tempo) (including played ones)")
                return key
            }
            
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
     * Gets a list of keys in the vicinity of the given key.
     * This includes the current key, the next key in the circle of fifths,
     * and the previous key in the circle of fifths.
     * 
     * @param currentKey The current key
     * @return An array of keys in the vicinity
     */
    private func getKeyOptions(from currentKey: MusicKey) -> [MusicKey] {
        var options = [currentKey]
        
        // Add the next key in the circle of fifths
        if let nextKey = getNextKey(from: currentKey) {
            options.append(nextKey)
        }
        
        // Add the previous key in the circle of fifths
        if let previousKey = getPreviousKey(from: currentKey) {
            options.append(previousKey)
        }
        
        return options
    }

    /**
     * Gets the previous key in the circle of fifths progression.
     * 
     * @param currentKey The current key
     * @return The previous key in the progression
     */
    private func getPreviousKey(from currentKey: MusicKey) -> MusicKey? {
        switch currentKey {
        case .C: return .F
        case .G: return .C
        case .D: return .G
        case .A: return .D
        case .E: return .A
        case .B: return .E
        case .FSharp: return .B
        case .CSharp: return .FSharp
        case .GSharp: return .CSharp
        case .DSharp: return .GSharp
        case .ASharp: return .DSharp
        case .F: return .ASharp
        }
    }

    /**
     * Sets the target tempo for the next song transition.
     * This doesn't stop playback but schedules a tempo change for the next transition.
     */
    private func scheduleTempoChange(_ tempo: Double) {
        print("SCHEDULING TEMPO CHANGE TO: \(tempo) BPM")
        
        // If not playing, apply immediately with a hard reset
        if !audioManager.isPlaying {
            print("Not playing - applying tempo change immediately")
            forceNewTempoSession(tempo)
            return
        }
        
        // Store the target tempo
        targetBPM = tempo
        
        // Mark that we have a pending tempo change
        pendingTempoChange = true
        
        // Reset the progress animation
        pendingTempoChangeProgress = 0.0
        
        // Start the progress animation
        withAnimation(.linear(duration: 2.0)) {
            pendingTempoChangeProgress = 1.0
        }
        
        // Update UI to show the new tempo is selected
        activeBPM = tempo
        if let index = tempoOptions.firstIndex(of: tempo) {
            tempoIndex = index
        }
        
        print("Tempo change scheduled - will apply at next loop boundary")
    }

    /**
     * Forces a completely new session with the selected tempo.
     * Used when not playing or when we need an immediate change.
     */
    private func forceNewTempoSession(_ tempo: Double) {
        print("FORCE NEW TEMPO SESSION: \(tempo)")
        
        // 1. Stop playback immediately
        audioManager.stopAllPlayers()
        
        // 2. Clear everything
        for sample in nowPlaying {
            audioManager.removeSampleFromPlay(sample)
        }
        nowPlaying.removeAll()
        sampleVolumes.removeAll()
        playedSampleIds.removeAll()
        
        // 3. Update tempo state
        activeBPM = tempo
        if let index = tempoOptions.firstIndex(of: tempo) {
            tempoIndex = index
        }
        audioManager.updateBPM(to: tempo)
        
        // 4. Find samples matching this tempo
        let tempoTolerance = 0.5
        let matchingSamples = samples.filter { abs($0.bpm - tempo) <= tempoTolerance }
        
        if matchingSamples.isEmpty {
            print("ERROR: No samples match tempo \(tempo)")
            return
        }
        
        print("Found \(matchingSamples.count) samples matching tempo \(tempo)")
        
        // 5. Pick a random key with samples at this tempo
        let keysWithSamples = Set(matchingSamples.map { $0.key })
        guard let randomKey = keysWithSamples.randomElement() else {
            print("ERROR: No keys with samples at tempo \(tempo)")
            return
        }
        
        activeKey = randomKey
        print("Selected key \(randomKey) for tempo \(tempo)")
        
        // 6. Pick two random samples
        let shuffled = matchingSamples.shuffled()
        var selectedSamples: [Sample] = []
        
        if shuffled.count >= 2 {
            selectedSamples = Array(shuffled.prefix(2))
        } else if !shuffled.isEmpty {
            selectedSamples = [shuffled[0]]
        }
        
        if selectedSamples.isEmpty {
            print("ERROR: Failed to select samples")
            return
        }
        
        print("Selected \(selectedSamples.count) samples: \(selectedSamples.map { $0.title })")
        
        // 7. Add samples to UI
        for sample in selectedSamples {
            nowPlaying.append(sample)
            sampleVolumes[sample.id] = 0.5
            print("Added to UI: \(sample.title)")
        }
        
        // 8. Load audio with delay
        Task {
            for sample in selectedSamples {
                do {
                    print("Loading audio for: \(sample.title)")
                    await audioManager.addSampleToPlay(sample)
                    audioManager.setVolume(for: sample, volume: 0.5)
                    print("Successfully loaded audio for: \(sample.title)")
                } catch {
                    print("ERROR loading audio for \(sample.title): \(error)")
                }
            }
            
            // 9. Start playback
            audioManager.play()
            print("Playback started")
        }
    }

    // Add this debug function to print all samples at a given tempo
    private func debugSamplesAtTempo(_ tempo: Double) {
        let tempoTolerance = 0.5
        let matchingSamples = samples.filter { abs($0.bpm - tempo) <= tempoTolerance }
        print("DEBUG: \(matchingSamples.count) samples at tempo \(tempo):")
        for sample in matchingSamples {
            print("  - \(sample.title) (Key: \(sample.key), BPM: \(sample.bpm))")
        }
    }
}

#Preview {
    ContentView(audioManager: AudioManager.shared)
}
