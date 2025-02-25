import Foundation
import AVFoundation

/// A player that synchronizes audio playback with a master beat clock
class ModernSyncedPlayer: SamplePlayerProtocol {
    // MARK: - Properties
    
    /// Unique identifier for this player
    let id: Int
    
    /// The sample being played
    let sample: Sample
    
    /// The audio engine this player belongs to
    private weak var engine: AVAudioEngine?
    
    /// The beat clock used for synchronization
    private weak var beatClock: BeatClock?
    
    /// The audio player node
    private let playerNode = AVAudioPlayerNode()
    
    /// The audio buffer containing the sample data
    private var audioBuffer: AVAudioPCMBuffer?
    
    /// Whether this player is currently playing
    var isPlaying: Bool {
        return playerNode.isPlaying
    }
    
    /// Volume level (0.0-1.0)
    var volume: Float {
        get { return playerNode.volume }
        set { playerNode.volume = newValue }
    }
    
    /// Current playback rate
    var playbackRate: Float = 1.0
    
    /// The beat at which playback started
    private var startBeat: Double = 0.0
    
    /// The last time drift was corrected
    private var lastDriftCorrectionTime: TimeInterval = 0.0
    
    /// Whether pitch is locked when tempo changes
    private var pitchLocked: Bool = false
    
    /// A time stretcher for pitch-locked playback
    private var timeStretcher: AVAudioUnitTimePitch?
    
    // MARK: - Initialization
    
    init(sample: Sample, engine: AVAudioEngine, beatClock: BeatClock, pitchLocked: Bool = false) {
        self.id = sample.id
        self.sample = sample
        self.engine = engine
        self.beatClock = beatClock
        self.pitchLocked = pitchLocked
        
        setupAudioNodes()
        loadAudioFile()
        adjustPlaybackRate()
    }
    
    // MARK: - Private Methods
    
    private func setupAudioNodes() {
        guard let engine = engine else { return }
        
        // Attach player node to engine
        engine.attach(playerNode)
        
        if pitchLocked {
            // Create and attach time stretcher for pitch-locked playback
            let timePitch = AVAudioUnitTimePitch()
            timeStretcher = timePitch
            engine.attach(timePitch)
            
            // Connect player -> time stretcher -> mixer
            engine.connect(playerNode, to: timePitch, format: nil)
            engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
        } else {
            // Connect player directly to mixer
            engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        }
    }
    
    private func loadAudioFile() {
        guard let url = Bundle.main.url(forResource: sample.fileName, withExtension: "mp3") else {
            print("Failed to find audio file: \(sample.fileName)")
            return
        }
        
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                print("Failed to create audio buffer")
                return
            }
            
            try file.read(into: buffer)
            audioBuffer = buffer
            
            print("Loaded audio file: \(sample.title) (ID: \(sample.id), BPM: \(sample.bpm))")
        } catch {
            print("Failed to load audio file: \(error)")
        }
    }
    
    private func adjustPlaybackRate() {
        guard let beatClock = beatClock else { return }
        
        // Calculate playback rate based on tempo ratio
        let tempoRatio = beatClock.bpm / sample.bpm
        playbackRate = Float(tempoRatio)
        
        if pitchLocked, let timeStretcher = timeStretcher {
            // For pitch-locked playback, set rate on time stretcher
            timeStretcher.rate = playbackRate
            
            // Reset player node rate to 1.0
            playerNode.rate = 1.0
        } else {
            // For normal playback, set rate directly on player
            playerNode.rate = playbackRate
        }
        
        print("Adjusted playback rate for \(sample.title): \(playbackRate)")
    }
    
    // MARK: - Public Methods
    
    /// Schedule playback to start at a specific beat
    func scheduleStart(atBeat beat: Double) {
        guard let buffer = audioBuffer, let beatClock = beatClock else { return }
        
        // Store start beat for drift calculations
        startBeat = beat
        
        // Get audio time for the specified beat
        let startTime = beatClock.timeForBeat(beat)
        
        // Schedule buffer to play at the specified time
        playerNode.scheduleBuffer(buffer, at: startTime, options: .loops, completionHandler: nil)
        
        // Start the player node
        playerNode.play()
        
        print("Scheduled \(sample.title) (ID: \(id)) to start at beat \(beat)")
    }
    
    /// Stop playback
    func stop() {
        playerNode.stop()
        print("Stopped \(sample.title) (ID: \(id))")
    }
    
    /// Update playback rate when tempo changes
    func updatePlaybackRate() {
        adjustPlaybackRate()
    }
    
    /// Set whether pitch is locked when tempo changes
    func setPitchLocked(_ locked: Bool) {
        if pitchLocked != locked {
            pitchLocked = locked
            
            // Reconnect audio nodes with new configuration
            stop()
            setupAudioNodes()
            adjustPlaybackRate()
        }
    }
    
    // MARK: - SamplePlayerProtocol Methods
    
    /// Get current phase position (0.0-1.0) in the loop
    func currentPhase() -> Double {
        guard let beatClock = beatClock else { return 0.0 }
        
        // Calculate current beat position
        let currentBeat = beatClock.currentBeat()
        
        // Calculate beats per loop
        let beatsPerLoop = Double(beatClock.beatsPerBar * beatClock.barsPerLoop)
        
        // Calculate phase within loop (0.0-1.0)
        let beatsSinceStart = currentBeat - startBeat
        let phase = (beatsSinceStart.truncatingRemainder(dividingBy: beatsPerLoop)) / beatsPerLoop
        
        return phase
    }
    
    /// Calculate drift from master clock in seconds
    func calculateDrift() -> Double {
        guard let beatClock = beatClock, let buffer = audioBuffer else { return 0.0 }
        
        // Get current beat position
        let currentBeat = beatClock.currentBeat()
        
        // Calculate expected beat position based on start beat and tempo
        let beatsSinceStart = currentBeat - startBeat
        let expectedBeatPosition = startBeat + beatsSinceStart
        
        // Calculate actual beat position based on player's sample time
        let sampleRate = buffer.format.sampleRate
        let beatsPerSecond = beatClock.bpm / 60.0
        let secondsPerBeat = 1.0 / beatsPerSecond
        
        // This is an approximation since we don't have direct access to the player's current sample position
        // In a real implementation, you'd need to track this more precisely
        let playerTime = playerNode.lastRenderTime
        let outputTime = playerNode.playerTime(forNodeTime: playerTime!)
        
        if let outputTime = outputTime {
            let sampleTime = outputTime.sampleTime
            let secondsPlayed = Double(sampleTime) / sampleRate
            let beatsPlayed = secondsPlayed / secondsPerBeat
            let actualBeatPosition = startBeat + beatsPlayed
            
            // Calculate drift in beats
            let driftInBeats = actualBeatPosition - expectedBeatPosition
            
            // Convert to seconds
            let driftInSeconds = driftInBeats * secondsPerBeat
            
            return driftInSeconds
        }
        
        return 0.0
    }
    
    /// Correct drift if it exceeds a threshold
    func correctDriftIfNeeded(thresholdSeconds: Double = 0.015) -> Bool {
        let currentTime = CACurrentMediaTime()
        
        // Don't correct drift too frequently
        if currentTime - lastDriftCorrectionTime < 1.0 {
            return false
        }
        
        // Calculate current drift
        let drift = calculateDrift()
        
        // If drift exceeds threshold, resync
        if abs(drift) > thresholdSeconds {
            // Get current beat position
            guard let beatClock = beatClock, let buffer = audioBuffer else { return false }
            let currentBeat = beatClock.currentBeat()
            
            // Stop current playback
            stop()
            
            // Restart at current beat
            scheduleStart(atBeat: currentBeat)
            
            // Update last correction time
            lastDriftCorrectionTime = currentTime
            
            print("Corrected drift of \(drift) seconds for \(sample.title) (ID: \(id))")
            return true
        }
        
        return false
    }
} 
