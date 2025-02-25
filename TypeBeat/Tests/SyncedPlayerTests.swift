import XCTest
import AVFoundation
@testable import TypeBeat

class SyncedPlayerTests: XCTestCase {
    
    // Test beat clocks at different tempos
    var clock84: BeatClock!
    var clock94: BeatClock!
    var clock102: BeatClock!
    
    // Simple mock player that doesn't try to override anything
    class MockPlayer {
        var isPlaying = false
        var buffer: AVAudioPCMBuffer?
        var scheduledTime: AVAudioTime?
        var playbackRate: Float = 1.0
        
        func play() {
            isPlaying = true
        }
        
        func stop() {
            isPlaying = false
        }
        
        func scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?) {
            self.buffer = buffer
            self.scheduledTime = when
        }
    }
    
    // Simple mock clock that doesn't extend BeatClock
    class MockClock {
        var bpm: Double
        var currentBeatValue: Double = 0
        var currentPhaseValue: Double = 0
        var beatsPerBar: Int = 4
        var barsPerLoop: Int = 4
        
        init(bpm: Double) {
            self.bpm = bpm
        }
        
        func currentBeat() -> Double {
            return currentBeatValue
        }
        
        func currentPhase() -> Double {
            return currentPhaseValue
        }
        
        func timeForBeat(_ beat: Double) -> AVAudioTime {
            // Simple mock implementation
            return AVAudioTime(sampleTime: Int64(beat * 48000), atRate: 48000)
        }
    }
    
    // A simplified version of SyncedPlayer for testing
    class TestSyncedPlayer {
        let player: MockPlayer
        let buffer: AVAudioPCMBuffer
        var clock: MockClock
        let originalBPM: Double
        let sampleId: Int
        let sampleName: String
        
        var isPlaying: Bool {
            return player.isPlaying
        }
        
        var startBeat: Double = 0
        
        init(player: MockPlayer, buffer: AVAudioPCMBuffer, clock: MockClock, 
             originalBPM: Double, sampleId: Int, sampleName: String) {
            self.player = player
            self.buffer = buffer
            self.clock = clock
            self.originalBPM = originalBPM
            self.sampleId = sampleId
            self.sampleName = sampleName
            
            adjustPlaybackRate()
        }
        
        func adjustPlaybackRate() {
            player.playbackRate = Float(clock.bpm / originalBPM)
        }
        
        func scheduleStart(atBeat beat: Double) {
            startBeat = beat
            let time = clock.timeForBeat(beat)
            player.scheduleBuffer(buffer, at: time)
            player.play()
        }
        
        func stop() {
            player.stop()
        }
        
        func currentPhase() -> Double {
            if !isPlaying {
                return 0
            }
            
            let beatsElapsed = clock.currentBeat() - startBeat
            let beatsPerLoop = Double(clock.beatsPerBar * clock.barsPerLoop)
            let phase = (beatsElapsed.truncatingRemainder(dividingBy: beatsPerLoop)) / beatsPerLoop
            
            return phase < 0 ? phase + 1.0 : phase
        }
        
        func calculateDrift() -> Double {
            if !isPlaying {
                return 0
            }
            
            // Calculate the current beat position of the player
            let currentClockBeat = clock.currentBeat()
            let playerBeat = startBeat + (currentClockBeat - startBeat)
            
            // Calculate the phase difference
            let beatsPerLoop = Double(clock.beatsPerBar * clock.barsPerLoop)
            
            // Get the position within the loop for both clock and player
            let clockLoopPosition = currentClockBeat.truncatingRemainder(dividingBy: beatsPerLoop)
            let playerLoopPosition = playerBeat.truncatingRemainder(dividingBy: beatsPerLoop)
            
            // Calculate the difference in beats
            var beatDiff = abs(playerLoopPosition - clockLoopPosition)
            if beatDiff > beatsPerLoop / 2 {
                beatDiff = beatsPerLoop - beatDiff
            }
            
            // Convert beat difference to seconds
            let secondsPerBeat = 60.0 / clock.bpm
            return beatDiff * secondsPerBeat
        }
        
        func correctDriftIfNeeded(thresholdSeconds: Double = 0.015) -> Bool {
            let drift = calculateDrift()
            
            if drift > thresholdSeconds {
                // Resync
                scheduleStart(atBeat: clock.currentBeat())
                return true
            }
            
            return false
        }
    }
    
    override func setUp() {
        super.setUp()
        
        // Create beat clocks with requested tempos
        let sampleRate = 48000.0
        clock84 = BeatClock(sampleRate: sampleRate, bpm: 84)
        clock94 = BeatClock(sampleRate: sampleRate, bpm: 94)
        clock102 = BeatClock(sampleRate: sampleRate, bpm: 102)
    }
    
    override func tearDown() {
        clock84 = nil
        clock94 = nil
        clock102 = nil
        super.tearDown()
    }
    
    // Helper to create a test buffer
    private func createTestBuffer(sampleRate: Double = 48000.0, durationSeconds: Double = 1.0) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        // Fill with a simple sine wave
        let sineFrequency = 440.0 // A4 note
        
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let value = sin(2.0 * .pi * sineFrequency * time)
            buffer.floatChannelData?[0][frame] = Float(value)
        }
        
        return buffer
    }
    
    // Test basic initialization and playback rate
    func testPlaybackRate() {
        let mockPlayer = MockPlayer()
        let testBuffer = createTestBuffer()
        let mockClock = MockClock(bpm: 102)
        
        let player = TestSyncedPlayer(
            player: mockPlayer,
            buffer: testBuffer,
            clock: mockClock,
            originalBPM: 84,
            sampleId: 1,
            sampleName: "Test Sample"
        )
        
        // Check initial playback rate
        XCTAssertEqual(mockPlayer.playbackRate, Float(102.0/84.0), accuracy: 0.001)
        
        // Change clock BPM
        mockClock.bpm = 94
        player.adjustPlaybackRate()
        
        // Check updated playback rate
        XCTAssertEqual(mockPlayer.playbackRate, Float(94.0/84.0), accuracy: 0.001)
    }
    
    // Test scheduling and phase calculation
    func testPhaseCalculation() {
        let mockPlayer = MockPlayer()
        let testBuffer = createTestBuffer()
        let mockClock = MockClock(bpm: 84)
        
        let player = TestSyncedPlayer(
            player: mockPlayer,
            buffer: testBuffer,
            clock: mockClock,
            originalBPM: 84,
            sampleId: 1,
            sampleName: "Test Sample"
        )
        
        // Start playback at beat 0
        player.scheduleStart(atBeat: 0)
        
        // Set current beat to 2
        mockClock.currentBeatValue = 2
        
        // In a 16-beat loop (4 beats/bar * 4 bars), 2 beats = 2/16 = 0.125 phase
        XCTAssertEqual(player.currentPhase(), 0.125, accuracy: 0.001)
        
        // Test with a different time signature
        let mockClock2 = MockClock(bpm: 84)
        mockClock2.beatsPerBar = 3 // 3/4 time
        mockClock2.barsPerLoop = 2 // 2 bars per loop = 6 beats total
        
        let player2 = TestSyncedPlayer(
            player: MockPlayer(),
            buffer: testBuffer,
            clock: mockClock2,
            originalBPM: 84,
            sampleId: 2,
            sampleName: "Mock Sample"
        )
        
        // Start playback at beat 0
        player2.scheduleStart(atBeat: 0)
        
        // Set current beat to 3
        mockClock2.currentBeatValue = 3
        
        // In a 6-beat loop, 3 beats = 3/6 = 0.5 phase
        XCTAssertEqual(player2.currentPhase(), 0.5, accuracy: 0.001)
    }
    
    // Test drift correction
    func testDriftCorrection() {
        let mockPlayer = MockPlayer()
        let testBuffer = createTestBuffer()
        let mockClock = MockClock(bpm: 94)
        
        // Set up a 4/4 time signature (16 beats per loop)
        mockClock.beatsPerBar = 4
        mockClock.barsPerLoop = 4
        
        // Create a custom TestSyncedPlayer with a simplified drift calculation
        class TestPlayerWithDrift: TestSyncedPlayer {
            var mockDrift = 0.0
            
            override func calculateDrift() -> Double {
                return mockDrift
            }
        }
        
        let player = TestPlayerWithDrift(
            player: mockPlayer,
            buffer: testBuffer,
            clock: mockClock,
            originalBPM: 94,
            sampleId: 3,
            sampleName: "Drift Test Sample"
        )
        
        // Start playback at beat 4
        mockClock.currentBeatValue = 4.0
        player.scheduleStart(atBeat: 4.0)
        
        // Test with small drift (under threshold)
        player.mockDrift = 0.010 // 10ms drift
        
        // Should not correct (under threshold)
        XCTAssertFalse(player.correctDriftIfNeeded(thresholdSeconds: 0.015))
        XCTAssertEqual(player.startBeat, 4.0) // Start beat should not change
        
        // Test with large drift (over threshold)
        player.mockDrift = 0.020 // 20ms drift
        mockClock.currentBeatValue = 6.0 // Clock is at beat 6
        
        // Should correct (over threshold)
        XCTAssertTrue(player.correctDriftIfNeeded(thresholdSeconds: 0.015))
        
        // Verify player was resynced to current beat
        XCTAssertEqual(player.startBeat, 6.0)
    }
    
    // Test multiple players in sync
    func testMultiplePlayerSync() {
        let mockClock = MockClock(bpm: 94)
        let testBuffer = createTestBuffer()
        
        let player1 = TestSyncedPlayer(
            player: MockPlayer(),
            buffer: testBuffer,
            clock: mockClock,
            originalBPM: 84,
            sampleId: 101,
            sampleName: "Sample 84"
        )
        
        let player2 = TestSyncedPlayer(
            player: MockPlayer(),
            buffer: testBuffer,
            clock: mockClock,
            originalBPM: 94,
            sampleId: 102,
            sampleName: "Sample 94"
        )
        
        let player3 = TestSyncedPlayer(
            player: MockPlayer(),
            buffer: testBuffer,
            clock: mockClock,
            originalBPM: 102,
            sampleId: 103,
            sampleName: "Sample 102"
        )
        
        // Schedule all players to start at the same beat
        let startBeat = 4.0
        player1.scheduleStart(atBeat: startBeat)
        player2.scheduleStart(atBeat: startBeat)
        player3.scheduleStart(atBeat: startBeat)
        
        // All players should be playing
        XCTAssertTrue(player1.isPlaying)
        XCTAssertTrue(player2.isPlaying)
        XCTAssertTrue(player3.isPlaying)
        
        // All players should have the same start beat
        XCTAssertEqual(player1.startBeat, startBeat)
        XCTAssertEqual(player2.startBeat, startBeat)
        XCTAssertEqual(player3.startBeat, startBeat)
    }
} 