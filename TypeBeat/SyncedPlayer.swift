import Foundation
import AVFoundation

/// A player that synchronizes audio playback with a BeatClock
class SyncedPlayer {
    // MARK: - Properties
    
    /// The audio player node
    private let player: AVAudioPlayerNode
    
    /// The audio buffer containing the sample
    private let buffer: AVAudioPCMBuffer
    
    /// The beat clock used for synchronization
    var clock: BeatClock
    
    /// The original BPM of the sample
    private let originalBPM: Double
    
    /// The varispeed node for tempo adjustment
    private let varispeedNode: AVAudioUnitVarispeed?
    
    /// The sample ID for identification
    let sampleId: Int
    
    /// The sample name
    let sampleName: String
    
    /// Whether the player is currently playing
    private(set) var isPlaying: Bool = false
    
    /// The beat position where this sample started
    private(set) var startBeat: Double = 0
    
    /// The current playback rate
    var playbackRate: Float {
        get {
            return varispeedNode?.rate ?? 1.0
        }
        set {
            varispeedNode?.rate = newValue
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize a new SyncedPlayer
    /// - Parameters:
    ///   - player: The AVAudioPlayerNode
    ///   - buffer: The audio buffer
    ///   - clock: The beat clock for synchronization
    ///   - originalBPM: The original BPM of the sample
    ///   - sampleId: The sample ID
    ///   - sampleName: The sample name
    ///   - varispeedNode: Optional varispeed node for tempo adjustment
    init(player: AVAudioPlayerNode, 
         buffer: AVAudioPCMBuffer, 
         clock: BeatClock, 
         originalBPM: Double, 
         sampleId: Int, 
         sampleName: String,
         varispeedNode: AVAudioUnitVarispeed? = nil) {
        
        self.player = player
        self.buffer = buffer
        self.clock = clock
        self.originalBPM = originalBPM
        self.sampleId = sampleId
        self.sampleName = sampleName
        self.varispeedNode = varispeedNode
        
        // Adjust playback rate based on clock BPM
        adjustPlaybackRate()
        
        print("SyncedPlayer initialized: \(sampleName) (ID: \(sampleId), BPM: \(originalBPM))")
    }
    
    // MARK: - Playback Control
    
    /// Schedule the player to start at a specific beat
    /// - Parameters:
    ///   - beat: The beat to start at (default: next beat)
    ///   - options: Playback options (default: looping)
    /// - Returns: The actual beat where playback will start
    @discardableResult
    func scheduleStart(atBeat beat: Double? = nil, options: AVAudioPlayerNodeBufferOptions = [.loops]) -> Double {
        // Stop any current playback
        stop()
        
        // Determine start beat (next beat if not specified)
        let startBeat = beat ?? clock.currentBeat().rounded(.up)
        
        // Get precise time for the beat
        let startTime = clock.timeForBeat(startBeat)
        
        // Schedule buffer with precise timing
        player.scheduleBuffer(buffer, at: startTime, options: options)
        
        // Store start beat for phase calculations
        self.startBeat = startBeat
        
        // Start playback
        player.play()
        isPlaying = true
        
        print("Scheduled \(sampleName) (ID: \(sampleId)) to start at beat \(startBeat)")
        return startBeat
    }
    
    /// Stop playback
    func stop() {
        player.stop()
        isPlaying = false
        print("Stopped \(sampleName) (ID: \(sampleId))")
    }
    
    /// Resync to the nearest beat boundary
    func resyncToNearestBeat() {
        // Get current beat and calculate nearest beat
        let currentBeat = clock.currentBeat()
        let nearestBeat = currentBeat.rounded()
        
        // Only resync if playing
        if isPlaying {
            print("Resyncing \(sampleName) (ID: \(sampleId)) from beat \(currentBeat) to \(nearestBeat)")
            scheduleStart(atBeat: nearestBeat)
        }
    }
    
    // MARK: - Tempo Adjustment
    
    /// Adjust playback rate based on clock BPM
    func adjustPlaybackRate() {
        guard let varispeedNode = varispeedNode else { return }
        
        // Calculate rate adjustment
        let clockBPM = clock.bpm
        let rateAdjustment = clockBPM / originalBPM
        
        // Apply to varispeed node
        varispeedNode.rate = Float(rateAdjustment)
        
        print("Adjusted rate for \(sampleName) (ID: \(sampleId)): \(varispeedNode.rate) (Original: \(originalBPM) BPM, Clock: \(clockBPM) BPM)")
    }
    
    // MARK: - Phase Calculation
    
    /// Calculate the current phase (0.0-1.0) within the loop
    /// - Returns: The current phase
    func currentPhase() -> Double {
        // Get current beat position
        let currentBeat = clock.currentBeat()
        
        // Calculate beats elapsed since start
        let beatsElapsed = currentBeat - startBeat
        
        // Calculate phase within the loop
        let beatsPerLoop = Double(clock.beatsPerBar * clock.barsPerLoop)
        let phase = (beatsElapsed.truncatingRemainder(dividingBy: beatsPerLoop)) / beatsPerLoop
        
        // Ensure phase is positive
        return phase < 0 ? phase + 1.0 : phase
    }
    
    /// Calculate drift from expected position
    /// - Returns: Drift in seconds
    func calculateDrift() -> Double {
        // Get current phase from clock
        let expectedPhase = clock.currentPhase()
        
        // Get actual phase from player
        let actualPhase = currentPhase()
        
        // Calculate phase difference (accounting for wrap-around)
        var phaseDiff = abs(actualPhase - expectedPhase)
        if phaseDiff > 0.5 {
            phaseDiff = 1.0 - phaseDiff
        }
        
        // Convert to seconds
        let beatsPerLoop = Double(clock.beatsPerBar * clock.barsPerLoop)
        let secondsPerLoop = (60.0 / clock.bpm) * beatsPerLoop
        return phaseDiff * secondsPerLoop
    }
    
    /// Check if drift exceeds threshold and resync if needed
    /// - Parameter thresholdSeconds: The drift threshold in seconds
    /// - Returns: Whether a resync was performed
    @discardableResult
    func correctDriftIfNeeded(thresholdSeconds: Double = 0.015) -> Bool {
        let drift = calculateDrift()
        
        if drift > thresholdSeconds {
            print("Drift detected for \(sampleName) (ID: \(sampleId)): \(String(format: "%.3f", drift * 1000))ms - resyncing")
            resyncToNearestBeat()
            return true
        }
        
        return false
    }
    
    /// Get detailed status information
    /// - Returns: A dictionary with status information
    func getStatus() -> [String: Any] {
        return [
            "sampleId": sampleId,
            "sampleName": sampleName,
            "isPlaying": isPlaying,
            "originalBPM": originalBPM,
            "clockBPM": clock.bpm,
            "playbackRate": playbackRate,
            "phase": currentPhase(),
            "drift": calculateDrift() * 1000, // in milliseconds
            "startBeat": startBeat
        ]
    }
}

class TrackManager {
    // MARK: - Properties
    
    // Core components
    private let audioEngine: AVAudioEngine
    private let beatClock: BeatClock
    private let mainMixer: AVAudioMixerNode
    
    // Beat pattern constants
    private let beatsPerBar = 4
    private let barsPerPattern = 4 // 4 bars = 16 beats for typical hip hop patterns
    
    // Track management
    private(set) var instrumentals: [Instrumental] = []
    private(set) var isPlaying: Bool = false
    
    // Synchronization settings
    private let driftThresholdSeconds: Double = 0.015 // 15ms
    private let syncCheckInterval: TimeInterval = 2.0 // Check sync every 2 seconds
    private var syncTimer: Timer?
    
    // Logging and monitoring
    private var driftLog: [(timestamp: Date, instrumentalId: Int, driftMs: Double)] = []
    private var isLoggingEnabled: Bool = true
    
    // MARK: - Initialization
    
    init(audioEngine: AVAudioEngine, beatClock: BeatClock) {
        self.audioEngine = audioEngine
        self.beatClock = beatClock
        self.mainMixer = audioEngine.mainMixerNode
        
        // Ensure audio engine is running
        startAudioEngineIfNeeded()
    }
    
    deinit {
        stopSyncTimer()
        stopAllInstrumentals()
    }
    
    // MARK: - Instrumental Management
    
    /// Adds a new instrumental to the mix
    @discardableResult
    func addInstrumental(sample: Sample) -> Instrumental {
        // Create audio player node
        let playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)
        
        // Load the audio buffer for this sample
        // In a real implementation, you would load from the file
        let buffer = loadAudioBuffer(for: sample)
        
        audioEngine.connect(playerNode, to: mainMixer, format: buffer.format)
        
        // Create synced player
        let syncedPlayer = SyncedPlayer(
            player: playerNode,
            buffer: buffer,
            clock: beatClock,
            originalBPM: sample.bpm,
            sampleId: sample.id,
            sampleName: sample.title
        )
        
        // Create instrumental
        let instrumental = Instrumental(
            id: nextInstrumentalId(),
            sample: sample,
            player: syncedPlayer,
            playerNode: playerNode
        )
        
        // Add to instrumentals array
        instrumentals.append(instrumental)
        
        // If already playing, start the new instrumental at the next pattern boundary
        if isPlaying {
            scheduleInstrumentalStart(instrumental)
        }
        
        logEvent("Added instrumental: \(sample.title) (\(sample.bpm) BPM, Key: \(sample.key))")
        
        return instrumental
    }
    
    // Add this method to the TrackManager class
    func findInstrumental(for sample: Sample) -> Instrumental? {
        return instrumentals.first { $0.sample.id == sample.id }
    } 
    
    /// Removes an instrumental from the mix
    func removeInstrumental(_ instrumental: Instrumental) {
        // Stop the instrumental
        instrumental.player.stop()
        
        // Detach from audio engine
        audioEngine.detach(instrumental.playerNode)
        
        // Remove from instrumentals array
        if let index = instrumentals.firstIndex(where: { $0.id == instrumental.id }) {
            instrumentals.remove(at: index)
        }
        
        logEvent("Removed instrumental: \(instrumental.sample.title)")
    }
    
    /// Removes all instrumentals
    func removeAllInstrumentals() {
        // Stop and remove each instrumental
        for instrumental in instrumentals {
            instrumental.player.stop()
            audioEngine.detach(instrumental.playerNode)
        }
        
        // Clear the array
        instrumentals.removeAll()
        
        logEvent("Removed all instrumentals")
    }
    
    // MARK: - Playback Control
    
    /// Starts playback of all instrumentals
    func startPlayback() {
        guard !isPlaying else { return }
        
        // Start the audio engine if needed
        startAudioEngineIfNeeded()
        
        // Schedule all instrumentals to start at the next pattern boundary
        for instrumental in instrumentals {
            scheduleInstrumentalStart(instrumental)
        }
        
        // Start sync timer
        startSyncTimer()
        
        isPlaying = true
        logEvent("Started playback")
    }
    
    /// Stops playback of all instrumentals
    func stopPlayback() {
        guard isPlaying else { return }
        
        // Stop all instrumentals
        for instrumental in instrumentals {
            instrumental.player.stop()
        }
        
        // Stop sync timer
        stopSyncTimer()
        
        isPlaying = false
        logEvent("Stopped playback")
    }
    
    /// Stops all instrumentals and removes them
    func stopAllInstrumentals() {
        stopPlayback()
        removeAllInstrumentals()
    }
    
    // MARK: - Synchronization
    
    /// Schedules an instrumental to start at the next pattern boundary
    private func scheduleInstrumentalStart(_ instrumental: Instrumental) {
        // Get current beat position - call the method
        let currentBeatValue = beatClock.currentBeat()
        
        // Calculate next pattern boundary (multiple of 16 beats)
        let patternLength = Double(beatsPerBar * barsPerPattern)
        let nextPatternBoundary = ceil(currentBeatValue / patternLength) * patternLength
        
        // Schedule the instrumental to start at the pattern boundary
        instrumental.player.scheduleStart(atBeat: nextPatternBoundary)
        
        logEvent("Scheduled \(instrumental.sample.title) to start at beat \(nextPatternBoundary)")
    }
    
    /// Starts the sync timer
    private func startSyncTimer() {
        stopSyncTimer() // Ensure no existing timer
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncCheckInterval, repeats: true) { [weak self] _ in
            self?.checkAndCorrectDrift()
        }
    }
    
    /// Stops the sync timer
    private func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    /// Checks and corrects drift for all instrumentals
    func checkAndCorrectDrift() {
        for instrumental in instrumentals where instrumental.isPlaying {
            // Calculate drift
            let drift = instrumental.player.calculateDrift()
            
            // Log drift
            if isLoggingEnabled {
                driftLog.append((
                    timestamp: Date(),
                    instrumentalId: instrumental.id,
                    driftMs: drift * 1000 // Convert to ms for logging
                ))
            }
            
            // Correct if needed
            if abs(drift) > driftThresholdSeconds {
                instrumental.player.correctDriftIfNeeded(thresholdSeconds: driftThresholdSeconds)
                logEvent("Corrected drift of \(String(format: "%.2f", drift * 1000))ms for \(instrumental.sample.title)")
            }
        }
    }
    
    // MARK: - Audio Engine Management
    
    /// Starts the audio engine if it's not already running
    private func startAudioEngineIfNeeded() {
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                logEvent("Started audio engine")
            } catch {
                logEvent("Failed to start audio engine: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Utilities
    
    /// Generates the next instrumental ID
    private func nextInstrumentalId() -> Int {
        return (instrumentals.map { $0.id }.max() ?? 0) + 1
    }
    
    /// Logs an event
    private func logEvent(_ message: String) {
        if isLoggingEnabled {
            print("TrackManager: \(message)")
        }
    }
    
    /// Loads an audio buffer for a sample
    private func loadAudioBuffer(for sample: Sample) -> AVAudioPCMBuffer {
        // In a real implementation, you would load the audio file from disk
        // For now, we'll create a synthetic buffer for testing
        
        let sampleRate = 44100.0
        let beatsPerBar = 4
        let barsPerPattern = 4
        let beatsPerPattern = beatsPerBar * barsPerPattern
        
        // Calculate duration for one pattern at the given tempo
        let secondsPerBeat = 60.0 / sample.bpm
        let patternDuration = secondsPerBeat * Double(beatsPerPattern)
        
        // Create buffer for the pattern
        let frameCount = AVAudioFrameCount(sampleRate * patternDuration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        // Fill buffer with a simple pattern
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let beatPosition = time / secondsPerBeat
            let beatInPattern = beatPosition.truncatingRemainder(dividingBy: Double(beatsPerPattern))
            
            // Create a sound with emphasis on beat positions
            let beatEmphasis = beatInPattern.truncatingRemainder(dividingBy: 1.0) < 0.1 ? 0.8 : 0.3
            let barEmphasis = beatInPattern.truncatingRemainder(dividingBy: Double(beatsPerBar)) < 0.1 ? 1.0 : 0.5
            
            // Use different base frequencies based on the key
            let baseFrequency: Double
            switch sample.key {
                case .C: baseFrequency = 261.63
                case .CSharp: baseFrequency = 277.18
                case .D: baseFrequency = 293.66
                case .DSharp: baseFrequency = 311.13
                case .E: baseFrequency = 329.63
                case .F: baseFrequency = 349.23
                case .FSharp: baseFrequency = 369.99
                case .G: baseFrequency = 392.00
                case .GSharp: baseFrequency = 415.30
                case .A: baseFrequency = 440.00
                case .ASharp: baseFrequency = 466.16
                case .B: baseFrequency = 493.88
            }
            
            // Create a sound with harmonics
            let value = sin(2.0 * .pi * baseFrequency * time) * 0.4 * beatEmphasis * barEmphasis +
                       sin(2.0 * .pi * baseFrequency * 2 * time) * 0.2 * beatEmphasis +
                       sin(2.0 * .pi * baseFrequency * 3 * time) * 0.1 * beatEmphasis
            
            // Normalize to avoid clipping
            let normalizedValue = Float(value * 0.7)
            
            // Set both channels
            buffer.floatChannelData?[0][frame] = normalizedValue
            buffer.floatChannelData?[1][frame] = normalizedValue
        }
        
        return buffer
    }
    
    // MARK: - Sample Finding
    
    /// Finds samples by tempo
    func findSamplesByTempo(tempo: Double, tolerance: Double = 1.0) -> [Sample] {
        return instrumentals.filter { abs($0.sample.bpm - tempo) <= tolerance }.map { $0.sample }
    }
    
    /// Finds samples by key
    func findSamplesByKey(key: MusicKey) -> [Sample] {
        return instrumentals.filter { $0.sample.key == key }.map { $0.sample }
    }
    
    /// Finds samples by tempo and key
    func findSamplesByTempoAndKey(tempo: Double, key: MusicKey, tempoTolerance: Double = 1.0) -> [Sample] {
        return instrumentals.filter { 
            abs($0.sample.bpm - tempo) <= tempoTolerance && 
            $0.sample.key == key 
        }.map { $0.sample }
    }
    
    // MARK: - Drift Statistics
    
    /// Gets drift statistics
    func getDriftStatistics() -> [String: Any] {
        guard !driftLog.isEmpty else {
            return ["message": "No drift data available"]
        }
        
        // Calculate overall statistics
        let driftValues = driftLog.map { $0.driftMs }
        let maxDrift = driftValues.max() ?? 0
        let minDrift = driftValues.min() ?? 0
        let avgDrift = driftValues.reduce(0, +) / Double(driftValues.count)
        
        // Group by instrumental
        var instrumentalDrift: [Int: [Double]] = [:]
        for entry in driftLog {
            if instrumentalDrift[entry.instrumentalId] == nil {
                instrumentalDrift[entry.instrumentalId] = []
            }
            instrumentalDrift[entry.instrumentalId]?.append(entry.driftMs)
        }
        
        // Calculate per-instrumental statistics
        var instrumentalStats: [String: Any] = [:]
        for (instrumentalId, driftValues) in instrumentalDrift {
            let instrumentalMax = driftValues.max() ?? 0
            let instrumentalMin = driftValues.min() ?? 0
            let instrumentalAvg = driftValues.reduce(0, +) / Double(driftValues.count)
            
            // Find the instrumental name
            let name = instrumentals.first(where: { $0.id == instrumentalId })?.sample.title ?? "Unknown"
            
            instrumentalStats[name] = [
                "max": String(format: "%.2f", instrumentalMax),
                "min": String(format: "%.2f", instrumentalMin),
                "avg": String(format: "%.2f", instrumentalAvg),
                "samples": driftValues.count
            ]
        }
        
        return [
            "overall": [
                "max": String(format: "%.2f", maxDrift),
                "min": String(format: "%.2f", minDrift),
                "avg": String(format: "%.2f", avgDrift),
                "samples": driftLog.count
            ],
            "byInstrumental": instrumentalStats,
            "thresholdMs": driftThresholdSeconds * 1000
        ]
    }
    
    /// Clears the drift log
    func clearDriftLog() {
        driftLog.removeAll()
        logEvent("Cleared drift log")
    }
}

// MARK: - Supporting Types

/// Represents an instrumental in the mix
class Instrumental {
    let id: Int
    let sample: Sample
    let player: SyncedPlayer
    let playerNode: AVAudioPlayerNode
    
    var isPlaying: Bool {
        return player.isPlaying
    }
    
    var volume: Float {
        get { return playerNode.volume }
        set { playerNode.volume = newValue }
    }
    
    init(id: Int, sample: Sample, player: SyncedPlayer, playerNode: AVAudioPlayerNode) {
        self.id = id
        self.sample = sample
        self.player = player
        self.playerNode = playerNode
    }
}

/// Represents a hip hop instrumental beat
struct Beat {
    let id: Int
    let name: String
    let tempo: Double
    let key: String
    let buffer: AVAudioPCMBuffer
    let tags: [String]
    let producer: String
    
    // Additional metadata
    let duration: TimeInterval
    let isLoop: Bool
    let dateAdded: Date
} 
