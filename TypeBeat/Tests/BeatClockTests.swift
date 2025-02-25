import XCTest
import AVFoundation
@testable import TypeBeat

class BeatClockTests: XCTestCase {
    
    // Test basic initialization
    func testInitialization() {
        let clock = BeatClock(sampleRate: 48000, bpm: 120)
        XCTAssertEqual(clock.bpm, 120)
        XCTAssertEqual(clock.beatsPerBar, 4)
        XCTAssertEqual(clock.barsPerLoop, 4)
    }
    
    // Test sample calculation for beats
    func testSampleForBeat() {
        let clock = BeatClock(sampleRate: 48000, bpm: 120)
        
        // At 120 BPM, one beat is 0.5 seconds
        // 0.5 seconds * 48000 Hz = 24000 samples
        XCTAssertEqual(clock.sampleForBeat(1), 24000)
        
        // 4 beats = 2 seconds = 96000 samples
        XCTAssertEqual(clock.sampleForBeat(4), 96000)
        
        // Test fractional beat
        XCTAssertEqual(clock.sampleForBeat(0.5), 12000)
    }
    
    // Test that BPM changes affect timing calculations
    func testBPMChanges() {
        let clock = BeatClock(sampleRate: 48000, bpm: 120)
        
        // Initial calculation at 120 BPM
        XCTAssertEqual(clock.sampleForBeat(1), 24000)
        
        // Change BPM to 60
        clock.bpm = 60
        
        // At 60 BPM, one beat is 1 second
        // 1 second * 48000 Hz = 48000 samples
        XCTAssertEqual(clock.sampleForBeat(1), 48000)
    }
    
    // Test that current beat calculation is reasonable
    func testCurrentBeat() {
        let clock = BeatClock(sampleRate: 48000, bpm: 120)
        
        // Initial beat should be very close to 0
        let initialBeat = clock.currentBeat()
        XCTAssertLessThan(initialBeat, 0.1)
        
        // Wait for approximately 1 beat (0.5 seconds at 120 BPM)
        Thread.sleep(forTimeInterval: 0.5)
        
        // Beat should now be approximately 1
        let afterBeat = clock.currentBeat()
        XCTAssertGreaterThan(afterBeat, 0.9)
        XCTAssertLessThan(afterBeat, 1.1)
    }
    
    // Test phase calculation
    func testPhaseCalculation() {
        let clock = BeatClock(sampleRate: 48000, bpm: 120, beatsPerBar: 4, barsPerLoop: 1)
        
        // In a 4-beat loop, beat 0 = phase 0.0
        let phase0 = clock.currentPhase()
        XCTAssertLessThan(phase0, 0.1)
        
        // Wait for approximately 2 beats (1 second at 120 BPM)
        Thread.sleep(forTimeInterval: 1.0)
        
        // Phase should now be approximately 0.5 (2/4)
        let phase2 = clock.currentPhase()
        XCTAssertGreaterThan(phase2, 0.45)
        XCTAssertLessThan(phase2, 0.55)
    }
    
    // Test time calculation for specific beats
    func testTimeForBeat() {
        let clock = BeatClock(sampleRate: 48000, bpm: 120)
        
        // Get time for beat 4
        let time4 = clock.timeForBeat(4)
        
        // Time should be valid
        XCTAssertTrue(time4.isSampleTimeValid)
        
        // Sample time should be startTime + 96000
        let expectedSampleTime = clock.timeForBeat(0).sampleTime + 96000
        XCTAssertEqual(time4.sampleTime, expectedSampleTime)
    }
    
    // Test next beat boundary calculation
    func testNextBeatBoundary() {
        let clock = BeatClock(sampleRate: 48000, bpm: 60)
        
        // Wait for a partial beat (0.3 seconds)
        Thread.sleep(forTimeInterval: 0.3)
        
        // Get time until next beat
        let timeUntilNext = clock.timeUntilNextBeatBoundary()
        
        // Should be approximately 0.7 seconds
        XCTAssertGreaterThan(timeUntilNext, 0.65)
        XCTAssertLessThan(timeUntilNext, 0.75)
    }
    
    // Test consistency between multiple clocks
    func testMultipleClockConsistency() {
        // Create two clocks with same parameters
        let clock1 = BeatClock(sampleRate: 48000, bpm: 120)
        let clock2 = BeatClock(sampleRate: 48000, bpm: 120)
        
        // Get time for beat 4 from both clocks
        let time1 = clock1.timeForBeat(4)
        let time2 = clock2.timeForBeat(4)
        
        // Calculate absolute time difference in seconds
        let diffSamples = abs(time1.sampleTime - time2.sampleTime)
        let diffSeconds = Double(diffSamples) / 48000.0
        
        // Difference should be very small (< 1ms)
        XCTAssertLessThan(diffSeconds, 0.001)
    }
    
    // Test thread safety with concurrent BPM changes
    func testThreadSafety() {
        let clock = BeatClock(sampleRate: 48000, bpm: 120)
        let expectation = XCTestExpectation(description: "Concurrent BPM changes")
        
        // Create a dispatch group for concurrent operations
        let group = DispatchGroup()
        
        // Perform 100 concurrent BPM changes
        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                clock.bpm = Double(100 + i % 20) // Values between 100-119
                group.leave()
            }
        }
        
        // Wait for all operations to complete
        group.notify(queue: .main) {
            // BPM should be one of the valid values
            XCTAssertGreaterThanOrEqual(clock.bpm, 100)
            XCTAssertLessThan(clock.bpm, 120)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
} 