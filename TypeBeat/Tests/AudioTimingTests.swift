import XCTest
@testable import TypeBeat

@MainActor
class AudioTimingTests: XCTestCase {
    var audioManager: AudioManager!
    
    override func setUp() async throws {
        audioManager = AudioManager.shared
        audioManager.stopAllPlayers()
        try await Task.sleep(until: .now + .milliseconds(500))
    }
    
    override func tearDown() async throws {
        audioManager.stopAllPlayers()
        try await Task.sleep(until: .now + .milliseconds(500))
    }
    
    func testSingleSamplePhaseAccuracy() async throws {
        let expectation = XCTestExpectation(description: "Phase accuracy test")
        
        // Use a sample at 84 BPM
        let sample = samples.first { $0.bpm == 84.0 }!
        print("\nTesting with sample: \(sample.title) at \(sample.bpm) BPM")
        
        // Expected phase change per millisecond at 84 BPM
        // One cycle (1.0) should take 714.29ms (60000ms/84beats)
        let expectedDeltaPerMs = 1.0 / (60000.0 / 84.0)  // ~0.001400
        
        // Configure audio manager
        audioManager.bpm = 84.0
        await audioManager.addSampleToPlay(sample)
        
        // Wait for setup
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        
        audioManager.play()
        
        // Wait for playback to stabilize
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        
        print("\nPhase Progression Analysis:")
        print("Time(ms)\tPhase\t\tDelta/ms\tExpected/ms\tError")
        print("----------------------------------------------------------------")
        
        var lastPhase = audioManager.getSamplePhase(for: sample.id)
        var lastTime = DispatchTime.now().uptimeNanoseconds
        var measurements: [(time: Double, phase: Double, delta: Double)] = []
        
        // Take measurements over 1 second
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms intervals
            
            let currentTime = DispatchTime.now().uptimeNanoseconds
            let currentPhase = audioManager.getSamplePhase(for: sample.id)
            
            let timeDeltaMs = Double(currentTime - lastTime) / 1_000_000.0
            
            // Handle phase wrapping
            var phaseDelta = currentPhase - lastPhase
            if phaseDelta < -0.5 {
                phaseDelta += 1.0
            } else if phaseDelta > 0.5 {
                phaseDelta -= 1.0
            }
            
            let deltaPerMs = phaseDelta / timeDeltaMs
            let error = abs(deltaPerMs - expectedDeltaPerMs)
            
            print(String(format: "%.1f\t%.4f\t%.6f\t%.6f\t%.6f",
                        timeDeltaMs,
                        currentPhase,
                        deltaPerMs,
                        expectedDeltaPerMs,
                        error))
            
            measurements.append((timeDeltaMs, currentPhase, deltaPerMs))
            
            // Allow for 25% variation in instantaneous measurements
            if measurements.count > 3 {  // Skip first few measurements during startup
                // Use rolling average of last 3 measurements
                let recentDeltas = measurements.suffix(3).map { $0.delta }
                let avgDelta = recentDeltas.reduce(0.0, +) / Double(recentDeltas.count)
                
                XCTAssertEqual(avgDelta, expectedDeltaPerMs, accuracy: expectedDeltaPerMs * 0.25,
                              "Average phase change rate over last 3 measurements (\(String(format: "%.6f", avgDelta))) doesn't match expected (\(String(format: "%.6f", expectedDeltaPerMs)))")
            }
            
            lastPhase = currentPhase
            lastTime = currentTime
        }
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    func testPhaseConsistencyAcrossReset() async throws {
        let expectation = XCTestExpectation(description: "Phase consistency test")
        
        let testSample = samples.first { $0.bpm == 84.0 }!
        print("\nTesting phase consistency with: \(testSample.title) at \(testSample.bpm) BPM")
        
        // First measurement
        await audioManager.addSampleToPlay(testSample)
        try await Task.sleep(for: .milliseconds(500))
        audioManager.play()
        
        try await Task.sleep(for: .seconds(1))
        let phase1 = audioManager.getSamplePhase(for: testSample.id)
        
        // Reset and second measurement
        audioManager.stopAllPlayers()
        try await Task.sleep(for: .milliseconds(500))
        
        await audioManager.addSampleToPlay(testSample)
        try await Task.sleep(for: .milliseconds(500))
        audioManager.play()
        
        try await Task.sleep(for: .seconds(1))
        let phase2 = audioManager.getSamplePhase(for: testSample.id)
        
        print("\nPhase Consistency Results:")
        print("Phase 1: \(String(format: "%.4f", phase1))")
        print("Phase 2: \(String(format: "%.4f", phase2))")
        print("Difference: \(String(format: "%.4f", abs(phase2 - phase1)))")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 5.0)
    }
} 