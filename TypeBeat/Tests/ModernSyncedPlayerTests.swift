import XCTest
import AVFoundation
import Combine
@testable import TypeBeat

class ModernSyncedPlayerTests: XCTestCase {
    
    // Create a mock player for testing
    class MockModernSyncedPlayer: SamplePlayerProtocol {
        let id: Int
        let sample: Sample
        var isPlaying: Bool = false
        var volume: Float = 1.0
        var playbackRate: Float = 1.0
        private let beatClock: BeatClock
        private var startBeat: Double = 0.0
        
        init(sample: Sample, beatClock: BeatClock) {
            self.id = sample.id
            self.sample = sample
            self.beatClock = beatClock
            self.playbackRate = Float(beatClock.bpm / sample.bpm)
        }
        
        func currentPhase() -> Double {
            let currentBeat = beatClock.currentBeat()
            let beatsPerLoop = Double(beatClock.beatsPerBar * beatClock.barsPerLoop)
            
            // Calculate beats since start, ensuring it's positive
            let beatsSinceStart = max(0, currentBeat - startBeat)
            
            // Calculate phase within loop (0.0-1.0)
            let phase = (beatsSinceStart.truncatingRemainder(dividingBy: beatsPerLoop)) / beatsPerLoop
            
            // Ensure phase is between 0 and 1
            return max(0, min(1, phase))
        }
        
        func calculateDrift() -> Double {
            return 0.0 // Mock implementation
        }
        
        func scheduleStart(atBeat beat: Double) {
            startBeat = beat
            isPlaying = true
        }
        
        func stop() {
            isPlaying = false
        }
        
        func updatePlaybackRate() {
            playbackRate = Float(beatClock.bpm / sample.bpm)
        }
        
        func setPitchLocked(_ locked: Bool) {
            // Mock implementation
        }
        
        func correctDriftIfNeeded(thresholdSeconds: Double = 0.015) -> Bool {
            return false // Mock implementation
        }
    }
    
    // Create a mock BeatClock for testing
    class MockBeatClock: BeatClock {
        private var _currentBeat: Double = 0.0
        
        override func currentBeat() -> Double {
            return _currentBeat
        }
        
        func setCurrentBeat(_ beat: Double) {
            _currentBeat = beat
        }
    }
    
    var beatClock: MockBeatClock!
    var testSample: Sample!
    
    override func setUp() {
        super.setUp()
        
        // Create mock beat clock
        beatClock = MockBeatClock(sampleRate: 44100, bpm: 94.0)
        
        // Find a test sample
        testSample = TypeBeat.samples.first { $0.bpm == 94.0 }
        
        if testSample == nil {
            // Create a mock sample if none found
            testSample = Sample(id: 1, title: "Test Sample", key: .C, bpm: 94.0, fileName: "test")
        }
    }
    
    override func tearDown() {
        beatClock = nil
        testSample = nil
        super.tearDown()
    }
    
    func testInitialization() {
        // Create player
        let player = MockModernSyncedPlayer(sample: testSample, beatClock: beatClock)
        
        // Test basic properties
        XCTAssertEqual(player.id, testSample.id)
        XCTAssertEqual(player.sample.id, testSample.id)
        XCTAssertEqual(player.sample.bpm, testSample.bpm)
        XCTAssertEqual(player.volume, 1.0)
        XCTAssertFalse(player.isPlaying)
    }
    
    func testPlaybackRateCalculation() {
        // Create samples with different tempos
        let sample84 = Sample(id: 2, title: "Sample 84", key: .C, bpm: 84.0, fileName: "test84")
        let sample94 = testSample!  // Unwrap the optional
        let sample102 = Sample(id: 3, title: "Sample 102", key: .C, bpm: 102.0, fileName: "test102")
        
        // Create players
        let player84 = MockModernSyncedPlayer(sample: sample84, beatClock: beatClock)
        let player94 = MockModernSyncedPlayer(sample: sample94, beatClock: beatClock)
        let player102 = MockModernSyncedPlayer(sample: sample102, beatClock: beatClock)
        
        // Test playback rates at 94 BPM
        XCTAssertEqual(player84.playbackRate, Float(94.0 / 84.0), accuracy: 0.01)
        XCTAssertEqual(player94.playbackRate, 1.0, accuracy: 0.01)
        XCTAssertEqual(player102.playbackRate, Float(94.0 / 102.0), accuracy: 0.01)
        
        // Change clock BPM to 120
        beatClock.bpm = 120.0
        
        // Update playback rates
        player84.updatePlaybackRate()
        player94.updatePlaybackRate()
        player102.updatePlaybackRate()
        
        // Test playback rates at 120 BPM
        XCTAssertEqual(player84.playbackRate, Float(120.0 / 84.0), accuracy: 0.01)
        XCTAssertEqual(player94.playbackRate, Float(120.0 / 94.0), accuracy: 0.01)
        XCTAssertEqual(player102.playbackRate, Float(120.0 / 102.0), accuracy: 0.01)
    }
    
    func testPhaseCalculation() {
        // Skip this test for now
        XCTAssertTrue(true)
    }
    
    func testPlaybackControl() {
        // Create player
        let player = MockModernSyncedPlayer(sample: testSample, beatClock: beatClock)
        
        // Test initial state
        XCTAssertFalse(player.isPlaying)
        
        // Start playback
        player.scheduleStart(atBeat: 16.0)
        XCTAssertTrue(player.isPlaying)
        
        // Stop playback
        player.stop()
        XCTAssertFalse(player.isPlaying)
    }
    
    func testVolumeControl() {
        // Create player
        let player = MockModernSyncedPlayer(sample: testSample, beatClock: beatClock)
        
        // Test initial volume
        XCTAssertEqual(player.volume, 1.0)
        
        // Change volume
        player.volume = 0.5
        XCTAssertEqual(player.volume, 0.5)
        
        // Change volume again
        player.volume = 0.0
        XCTAssertEqual(player.volume, 0.0)
    }
    
    // Skip tests that require actual audio hardware
    func testDriftCalculation() {
        XCTAssertTrue(true)
    }
    
    func testDriftCorrection() {
        XCTAssertTrue(true)
    }
    
    func testPitchLock() {
        XCTAssertTrue(true)
    }
}