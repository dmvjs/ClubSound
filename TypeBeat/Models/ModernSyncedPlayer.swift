import AVFoundation
import Combine

/// A modern audio player that synchronizes playback with a beat clock
class ModernSyncedPlayer: ObservableObject, Identifiable, SamplePlayerProtocol {
    // MARK: - Properties
    
    /// Unique identifier for this player (for Identifiable conformance)
    let uuid: UUID = UUID()
    
    /// Identifier for SamplePlayerProtocol conformance
    var id: Int {
        return sample.id
    }
    
    /// The audio sample being played
    let sample: Sample
    
    /// The beat clock used for synchronization
    let beatClock: BeatClock
    
    /// The audio engine
    let engine: AVAudioEngine
    
    /// Whether pitch is locked when tempo changes
    let pitchLocked: Bool
    
    /// Sample ID for SamplePlayerProtocol conformance
    var sampleId: Int {
        return sample.id
    }
    
    /// The underlying AVAudioPlayer
    private var player: AVAudioPlayer?
    
    /// The beat at which playback started or will start
    private(set) var startBeat: Double = 0.0
    
    /// Whether the player is currently playing
    @Published private(set) var isPlaying: Bool = false
    
    /// The current playback volume (0.0 to 1.0)
    var volume: Float = 1.0 {
        didSet {
            player?.volume = volume
        }
    }
    
    /// Whether the player is muted
    var isMuted: Bool = false {
        didSet {
            player?.volume = isMuted ? 0.0 : volume
        }
    }
    
    /// Pan position (-1.0 to 1.0)
    var pan: Float = 0.0 {
        didSet {
            player?.pan = pan
        }
    }
    
    /// The current playback rate
    var playbackRate: Float = 1.0 {
        didSet {
            player?.rate = playbackRate
            player?.enableRate = true
        }
    }
    
    /// Timer for monitoring and correcting drift
    private var driftCorrectionTimer: Timer?
    
    /// The cached seconds per beat value
    private var cachedSecondsPerBeat: Double?
    
    /// The BPM value when the cache was last updated
    private var cachedBPM: Double = 0
    
    // MARK: - Initialization
    
    /// Initialize with a sample and beat clock
    /// - Parameters:
    ///   - sample: The audio sample to play
    ///   - engine: The audio engine
    ///   - beatClock: The beat clock for synchronization
    ///   - pitchLocked: Whether pitch is locked when tempo changes
    init(sample: Sample, engine: AVAudioEngine, beatClock: BeatClock, pitchLocked: Bool) {
        self.sample = sample
        self.engine = engine
        self.beatClock = beatClock
        self.pitchLocked = pitchLocked
        
        setupPlayer()
        setupDriftCorrection()
    }
    
    deinit {
        driftCorrectionTimer?.invalidate()
        stop()
    }
    
    // MARK: - Setup
    
    /// Set up the audio player
    private func setupPlayer() {
        // Get the URL for the sample file
        guard let url = getAudioFileURL() else {
            print("Error: Could not create URL for sample file \(sample.fileName)")
            return
        }
        
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.volume = volume
            player?.enableRate = true
            player?.rate = playbackRate
            
            // Set to loop by default for beat-based samples
            player?.numberOfLoops = -1
        } catch {
            print("Error creating audio player: \(error.localizedDescription)")
        }
    }
    
    /// Get the URL for the audio file
    private func getAudioFileURL() -> URL? {
        // Look for the file in the app bundle
        if let url = Bundle.main.url(forResource: sample.fileName, withExtension: "mp3") {
            return url
        }
        
        // If not found in bundle, check the Documents directory
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsDirectory?.appendingPathComponent("\(sample.fileName).mp3")
    }
    
    /// Set up the drift correction timer
    private func setupDriftCorrection() {
        driftCorrectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            _ = self.correctDriftIfNeeded()
        }
    }
    
    // MARK: - Playback Control
    
    /// Start playback
    func play() {
        guard let player = player else { return }
        
        startBeat = beatClock.currentBeat()
        player.currentTime = 0
        player.play()
        isPlaying = true
    }
    
    /// Stop playback
    func stop() {
        player?.stop()
        isPlaying = false
    }
    
    /// Toggle playback (required by SamplePlayerProtocol)
    func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }
    
    /// Schedule playback to start at a specific beat
    /// - Parameter beat: The beat at which to start playback
    func scheduleStart(atBeat beat: Double) {
        startBeat = beat
        
        // If the beat is in the future, wait until then to start
        let currentBeat = beatClock.currentBeat()
        if beat > currentBeat {
            let delayInBeats = beat - currentBeat
            let delayInSeconds = getSecondsPerBeat() * delayInBeats
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delayInSeconds) { [weak self] in
                guard let self = self else { return }
                self.play()
            }
        } else {
            // If the beat is now or in the past, start immediately
            play()
        }
    }
    
    /// Play at a specific beat (required by SamplePlayerProtocol)
    func playAtBeat(_ beat: Double) {
        scheduleStart(atBeat: beat)
    }
    
    // MARK: - Synchronization
    
    /// Calculate seconds per beat based on the current tempo with caching
    /// - Returns: Seconds per beat
    private func getSecondsPerBeat() -> Double {
        let currentBPM = beatClock.bpm
        
        // If BPM has changed or cache is empty, recalculate
        if cachedSecondsPerBeat == nil || currentBPM != cachedBPM {
            cachedSecondsPerBeat = 60.0 / currentBPM
            cachedBPM = currentBPM
        }
        
        return cachedSecondsPerBeat!
    }
    
    /// Update the playback rate based on tempo changes
    func updatePlaybackRate() {
        // Calculate the ratio between sample BPM and current BPM
        let tempoRatio = Double(sample.bpm) / beatClock.bpm
        
        if pitchLocked {
            // If pitch is locked, adjust playback rate to match tempo
            playbackRate = Float(tempoRatio)
        } else {
            // If pitch is not locked, keep original playback rate
            playbackRate = 1.0
        }
    }
    
    /// Calculate the current phase of playback (0.0 to 1.0)
    /// - Returns: The current phase within the loop
    func currentPhase() -> Double {
        let currentBeat = beatClock.currentBeat()
        let beatsPerLoop = Double(beatClock.beatsPerBar * beatClock.barsPerLoop)
        
        // Calculate beats since start
        let beatsSinceStart = currentBeat - startBeat
        
        // Handle negative values (scheduling for future)
        if beatsSinceStart < 0 {
            return 0.0
        }
        
        // Calculate phase within loop (0.0-1.0)
        var phase = (beatsSinceStart.truncatingRemainder(dividingBy: beatsPerLoop)) / beatsPerLoop
        
        // Ensure phase is between 0 and 1
        if phase < 0 {
            phase += 1.0
        }
        
        return max(0, min(1, phase))
    }
    
    /// Calculate how much the playback has drifted from where it should be
    /// - Returns: The drift in seconds
    func calculateDrift() -> Double {
        guard let player = player, isPlaying else { return 0 }
        
        let currentBeat = beatClock.currentBeat()
        let beatsSinceStart = currentBeat - startBeat
        
        // If playback hasn't started yet, there's no drift
        if beatsSinceStart < 0 {
            return 0
        }
        
        // Calculate expected position in seconds
        let expectedPosition = getSecondsPerBeat() * beatsSinceStart
        
        // Get actual position
        let actualPosition = player.currentTime
        
        // Calculate drift
        return abs(expectedPosition - actualPosition)
    }
    
    /// Correct drift if it exceeds the threshold
    /// - Parameter thresholdSeconds: The threshold in seconds
    /// - Returns: Whether drift correction was applied
    func correctDriftIfNeeded(thresholdSeconds: Double = 0.015) -> Bool {
        let drift = calculateDrift()
        
        // If drift is significant but not extreme
        if drift > thresholdSeconds && drift < 0.05 {
            // Gradually adjust playback rate to catch up/slow down
            // This is gentler than restarting the sample
            let correctionFactor = 1.0 + (drift * 0.5) // Proportional correction
            
            // Apply temporary rate adjustment
            let originalRate = playbackRate
            playbackRate = Float(Double(originalRate) * correctionFactor)
            
            // Schedule return to normal rate after a short time
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.playbackRate = originalRate
            }
            
            return true
        }
        // For extreme drift, use the traditional reset approach
        else if drift >= 0.05 {
            // Reset playback position
            let currentBeat = beatClock.currentBeat()
            stop()
            scheduleStart(atBeat: currentBeat)
            
            return true
        }
        
        return false
    }
} 