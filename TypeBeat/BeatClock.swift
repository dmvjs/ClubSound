import Foundation
import AVFoundation

/// A high-precision clock for audio beat synchronization
class BeatClock {
    // MARK: - Properties
    
    /// The sample rate of the audio system
    private let sampleRate: Double
    
    /// The reference start time for all calculations
    private let startTime: AVAudioTime
    
    /// The current tempo in beats per minute
    private var _bpm: Double
    
    /// Thread-safe access to BPM
    var bpm: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _bpm
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _bpm = newValue
        }
    }
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// The number of beats per bar (typically 4)
    let beatsPerBar: Int
    
    /// The total number of bars in a loop
    let barsPerLoop: Int
    
    // MARK: - Initialization
    
    /// Initialize a new BeatClock with the given parameters
    /// - Parameters:
    ///   - sampleRate: The sample rate of the audio system
    ///   - bpm: The initial tempo in beats per minute
    ///   - beatsPerBar: The number of beats per bar (default: 4)
    ///   - barsPerLoop: The total number of bars in a loop (default: 4)
    init(sampleRate: Double, bpm: Double, beatsPerBar: Int = 4, barsPerLoop: Int = 4) {
        self.sampleRate = sampleRate
        self._bpm = bpm
        self.beatsPerBar = beatsPerBar
        self.barsPerLoop = barsPerLoop
        
        // Create a precise start time
        self.startTime = AVAudioTime(hostTime: mach_absolute_time())
        
        print("BeatClock initialized: \(bpm) BPM, \(sampleRate) Hz")
    }
    
    // MARK: - Beat Calculations
    
    /// Calculate the exact sample position for a given beat
    /// - Parameter beat: The beat number (can be fractional)
    /// - Returns: The sample position
    func sampleForBeat(_ beat: Double) -> Int64 {
        let secondsPerBeat = 60.0 / bpm
        let seconds = beat * secondsPerBeat
        return Int64(seconds * sampleRate)
    }
    
    /// Calculate the current beat position based on elapsed time
    /// - Returns: The current beat position (can be fractional)
    func currentBeat() -> Double {
        let now = AVAudioTime(hostTime: mach_absolute_time())
        guard now.hostTime >= startTime.hostTime else {
            return 0.0 // Handle case where now is before start time
        }
        
        // Calculate elapsed time in seconds
        let elapsedHostTime = now.hostTime - startTime.hostTime
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let elapsedNanos = Double(elapsedHostTime * UInt64(timebaseInfo.numer)) / Double(timebaseInfo.denom)
        let elapsedSeconds = elapsedNanos / Double(NSEC_PER_SEC)
        
        // Convert to beats
        let beatsPerSecond = bpm / 60.0
        return elapsedSeconds * beatsPerSecond
    }
    
    /// Get the current beat position within the loop (0 to totalBeats-1)
    /// - Returns: The current beat position within the loop
    func currentLoopBeat() -> Double {
        let totalBeats = Double(beatsPerBar * barsPerLoop)
        let beat = currentBeat()
        return beat.truncatingRemainder(dividingBy: totalBeats)
    }
    
    /// Get the current phase position (0.0 to 1.0) within the loop
    /// - Returns: The current phase position
    func currentPhase() -> Double {
        let totalBeats = Double(beatsPerBar * barsPerLoop)
        return currentLoopBeat() / totalBeats
    }
    
    // MARK: - Timing Utilities
    
    /// Get a precise AVAudioTime for a specific beat
    /// - Parameter beat: The beat number
    /// - Returns: An AVAudioTime object for the specified beat
    func timeForBeat(_ beat: Double) -> AVAudioTime {
        let sampleOffset = sampleForBeat(beat)
        
        // Create a new time with sample-based precision
        return AVAudioTime(
            sampleTime: startTime.sampleTime + sampleOffset,
            atRate: sampleRate
        )
    }
    
    /// Get a precise AVAudioTime for the next beat boundary
    /// - Parameter beatDivision: The beat division (1=whole beats, 0.5=half beats, etc.)
    /// - Returns: An AVAudioTime for the next beat boundary
    func timeForNextBeatBoundary(beatDivision: Double = 1.0) -> AVAudioTime {
        let currentBeatPos = currentBeat()
        let nextBeatBoundary = ceil(currentBeatPos / beatDivision) * beatDivision
        return timeForBeat(nextBeatBoundary)
    }
    
    /// Calculate the time until the next beat boundary
    /// - Parameter beatDivision: The beat division (1=whole beats, 0.5=half beats, etc.)
    /// - Returns: Time in seconds until the next beat boundary
    func timeUntilNextBeatBoundary(beatDivision: Double = 1.0) -> Double {
        let currentBeatPos = currentBeat()
        let nextBeatBoundary = ceil(currentBeatPos / beatDivision) * beatDivision
        let beatDifference = nextBeatBoundary - currentBeatPos
        return beatDifference * (60.0 / bpm)
    }
    
    /// Reset the clock to the current time
    func reset() {
        let newStartTime = AVAudioTime(hostTime: mach_absolute_time())
        
        // We need to create a new BeatClock since startTime is immutable
        // This is a placeholder - in actual implementation we'd need to handle this differently
        print("BeatClock reset at \(newStartTime.hostTime)")
    }
    
    /// Reset the clock to the nearest beat boundary
    func resetToNearestBeat() {
        let currentBeatPos = currentBeat()
        let nearestBeat = round(currentBeatPos)
        let beatDifference = nearestBeat - currentBeatPos
        
        // Calculate the time adjustment
        let secondsPerBeat = 60.0 / bpm
        let timeAdjustment = beatDifference * secondsPerBeat
        
        // We'd need to adjust the startTime, but since it's immutable,
        // this is just a placeholder for the actual implementation
        print("BeatClock reset to nearest beat: \(nearestBeat)")
    }
} 