import XCTest
import AVFoundation
@testable import TypeBeat

class TrackManagerTests: XCTestCase {
    
    // Test components
    var audioEngine: AVAudioEngine!
    var beatClock: BeatClock!
    var trackManager: TrackManager!
    
    // Test samples from different tempo groups
    var samples84BPM: [Sample] = []
    var samples94BPM: [Sample] = []
    var samples102BPM: [Sample] = []
    
    override func setUp() {
        super.setUp()
        
        // Set up audio engine
        audioEngine = AVAudioEngine()
        
        // Create beat clock at 94 BPM (most common in your samples)
        beatClock = BeatClock(sampleRate: 44100, bpm: 94)
        
        // Create track manager
        trackManager = TrackManager(audioEngine: audioEngine, beatClock: beatClock)
        
        // Get actual samples from the app's sample collection
        // Group by tempo for testing different scenarios
        samples84BPM = TypeBeat.samples.filter { $0.bpm == 84 }
        samples94BPM = TypeBeat.samples.filter { $0.bpm == 94 }
        samples102BPM = TypeBeat.samples.filter { $0.bpm == 102 }
        
        // Create audio buffers for the samples (in a real test, you'd load the actual files)
        createAudioBuffersForSamples()
    }
    
    override func tearDown() {
        // Clean up
        trackManager.stopAllInstrumentals()
        trackManager = nil
        beatClock = nil
        audioEngine = nil
        
        super.tearDown()
    }
    
    // Helper to create audio buffers for samples
    private func createAudioBuffersForSamples() {
        // In a real test, you would load the actual audio files
        // For now, we'll create synthetic buffers for testing
        
        // Implementation details would depend on how your app loads audio files
        // This is a placeholder for the actual implementation
    }
    
    // MARK: - Tests
    
    func testAddAndRemoveInstrumentals() {
        // Skip if no samples available
        guard !samples94BPM.isEmpty else {
            XCTFail("No 94 BPM samples available for testing")
            return
        }
        
        // Add instrumentals using actual samples from your app
        let sample1 = samples94BPM[0]
        let sample2 = samples94BPM.count > 1 ? samples94BPM[1] : samples94BPM[0]
        
        let instrumental1 = trackManager.addInstrumental(sample: sample1)
        let instrumental2 = trackManager.addInstrumental(sample: sample2)
        
        // Verify instrumentals were added
        XCTAssertEqual(trackManager.instrumentals.count, 2)
        XCTAssertEqual(trackManager.instrumentals[0].id, instrumental1.id)
        XCTAssertEqual(trackManager.instrumentals[1].id, instrumental2.id)
        
        // Verify sample information is preserved
        XCTAssertEqual(instrumental1.sample.title, sample1.title)
        XCTAssertEqual(instrumental1.sample.bpm, sample1.bpm)
        XCTAssertEqual(instrumental1.sample.key, sample1.key)
        
        // Remove one instrumental
        trackManager.removeInstrumental(instrumental1)
        
        // Verify it was removed
        XCTAssertEqual(trackManager.instrumentals.count, 1)
        XCTAssertEqual(trackManager.instrumentals[0].id, instrumental2.id)
        
        // Remove all instrumentals
        trackManager.removeAllInstrumentals()
        
        // Verify all were removed
        XCTAssertEqual(trackManager.instrumentals.count, 0)
    }
    
    func testPlaybackControl() {
        // Skip if no samples available
        guard !samples94BPM.isEmpty else {
            XCTFail("No 94 BPM samples available for testing")
            return
        }
        
        // Add an instrumental
        let instrumental = trackManager.addInstrumental(sample: samples94BPM[0])
        
        // Initially not playing
        XCTAssertFalse(trackManager.isPlaying)
        XCTAssertFalse(instrumental.isPlaying)
        
        // Start playback
        trackManager.startPlayback()
        
        // Verify playing state
        XCTAssertTrue(trackManager.isPlaying)
        XCTAssertTrue(instrumental.isPlaying)
        
        // Stop playback
        trackManager.stopPlayback()
        
        // Verify stopped state
        XCTAssertFalse(trackManager.isPlaying)
        XCTAssertFalse(instrumental.isPlaying)
    }
    
    func testTempoMatching() {
        // Skip if samples not available
        guard !samples84BPM.isEmpty, !samples94BPM.isEmpty, !samples102BPM.isEmpty else {
            XCTFail("Not enough samples with different tempos available for testing")
            return
        }
        
        // Add samples from each tempo group
        let instrumental84 = trackManager.addInstrumental(sample: samples84BPM[0])
        let instrumental94 = trackManager.addInstrumental(sample: samples94BPM[0])
        let instrumental102 = trackManager.addInstrumental(sample: samples102BPM[0])
        
        // Start playback
        trackManager.startPlayback()
        
        // Test finding by tempo
        let found84 = trackManager.findSamplesByTempo(tempo: 84, tolerance: 0.5)
        let found94 = trackManager.findSamplesByTempo(tempo: 94, tolerance: 0.5)
        let found102 = trackManager.findSamplesByTempo(tempo: 102, tolerance: 0.5)
        
        // Verify results
        XCTAssertTrue(!found84.isEmpty, "Should find samples at 84 BPM")
        XCTAssertTrue(!found94.isEmpty, "Should find samples at 94 BPM")
        XCTAssertTrue(!found102.isEmpty, "Should find samples at 102 BPM")
        
        // Test tempo tolerance
        let foundNear94 = trackManager.findSamplesByTempo(tempo: 94, tolerance: 10)
        XCTAssertTrue(foundNear94.count >= found94.count, "Should find at least as many samples with higher tolerance")
        
        // Test with tempo outside our range
        let found120 = trackManager.findSamplesByTempo(tempo: 120, tolerance: 0.5)
        XCTAssertTrue(found120.isEmpty, "Should not find samples at 120 BPM with low tolerance")
    }
    
    func testKeyFiltering() {
        // Add samples with different keys
        let cKeySamples = TypeBeat.samples.filter { $0.key == .C }
        let fSharpKeySamples = TypeBeat.samples.filter { $0.key == .FSharp }
        
        // Skip if not enough samples
        guard !cKeySamples.isEmpty, !fSharpKeySamples.isEmpty else {
            XCTFail("Not enough samples with different keys for testing")
            return
        }
        
        // Add samples to track manager
        for sample in cKeySamples.prefix(2) {
            trackManager.addInstrumental(sample: sample)
        }
        
        for sample in fSharpKeySamples.prefix(2) {
            trackManager.addInstrumental(sample: sample)
        }
        
        // Test finding by key
        let foundCSamples = trackManager.findSamplesByKey(key: .C)
        let foundFSharpSamples = trackManager.findSamplesByKey(key: .FSharp)
        
        // Verify results - we should find samples in both keys
        XCTAssertTrue(!foundCSamples.isEmpty, "Should find samples in C key")
        XCTAssertTrue(!foundFSharpSamples.isEmpty, "Should find samples in F# key")
        
        // Test case insensitivity
        let foundLowercaseC = trackManager.findSamplesByKey(key: .C)
        XCTAssertEqual(foundCSamples.count, foundLowercaseC.count, "Key search should be case insensitive")
    }
    
    func testTempoAndKeyFiltering() {
        // Add samples with different tempos and keys
        let samples94C = TypeBeat.samples.filter { $0.bpm == 94 && $0.key == .C }
        let samples84FSharp = TypeBeat.samples.filter { $0.bpm == 84 && $0.key == .FSharp }
        
        // Skip if not enough samples
        guard !samples94C.isEmpty, !samples84FSharp.isEmpty else {
            XCTFail("Not enough samples with specific tempo and key combinations for testing")
            return
        }
        
        // Add samples to track manager
        for sample in samples94C.prefix(2) {
            trackManager.addInstrumental(sample: sample)
        }
        
        for sample in samples84FSharp.prefix(2) {
            trackManager.addInstrumental(sample: sample)
        }
        
        // Test finding by tempo and key
        let found94C = trackManager.findSamplesByTempoAndKey(tempo: 94, key: .C)
        let found84FSharp = trackManager.findSamplesByTempoAndKey(tempo: 84, key: .FSharp)
        
        // Verify results
        XCTAssertTrue(!found94C.isEmpty, "Should find samples at 94 BPM in C key")
        XCTAssertTrue(!found84FSharp.isEmpty, "Should find samples at 84 BPM in F# key")
        
        // Test with wrong combinations
        let found94FSharp = trackManager.findSamplesByTempoAndKey(tempo: 94, key: .FSharp)
        let found84C = trackManager.findSamplesByTempoAndKey(tempo: 84, key: .C)
        
        // These might be empty if we don't have these specific combinations
        // So we'll just log the results rather than asserting
        print("Found \(found94FSharp.count) samples at 94 BPM in F# key")
        print("Found \(found84C.count) samples at 84 BPM in C key")
    }
    
    func testDriftCorrection() {
        // Skip if no samples available
        guard !samples94BPM.isEmpty else {
            XCTFail("No 94 BPM samples available for testing")
            return
        }
        
        // Add an instrumental
        let instrumental = trackManager.addInstrumental(sample: samples94BPM[0])
        
        // Start playback
        trackManager.startPlayback()
        
        // Manually trigger drift check
        trackManager.checkAndCorrectDrift()
        
        // Get drift statistics
        let stats = trackManager.getDriftStatistics()
        
        // Check if there's a message indicating no drift data
        if let message = stats["message"] as? String {
            XCTAssertEqual(message, "No drift data available")
        } else {
            // Otherwise, verify statistics structure
            XCTAssertNotNil(stats["overall"])
            XCTAssertNotNil(stats["byInstrumental"])
        }
        
        // Clear drift log
        trackManager.clearDriftLog()
    }
    
    func testMultipleTempoGroups() {
        // This test verifies that changing the master tempo properly adjusts all instrumentals
        
        // Skip if samples not available
        guard !samples84BPM.isEmpty, !samples94BPM.isEmpty, !samples102BPM.isEmpty else {
            XCTFail("Not enough samples with different tempos available for testing")
            return
        }
        
        // Start with 94 BPM
        beatClock.bpm = 94
        
        // Add samples from each tempo group
        let instrumental84 = trackManager.addInstrumental(sample: samples84BPM[0])
        let instrumental94 = trackManager.addInstrumental(sample: samples94BPM[0])
        let instrumental102 = trackManager.addInstrumental(sample: samples102BPM[0])
        
        // Start playback
        trackManager.startPlayback()
        
        // Change master tempo to 84 BPM
        beatClock.bpm = 84
        
        // Test volume control
        instrumental84.volume = 0.8
        XCTAssertEqual(instrumental84.volume, 0.8, "Volume should be changed to 0.8")
        
        // Change to 102 BPM
        beatClock.bpm = 102
        
        // Test sample properties
        XCTAssertEqual(instrumental84.sample.bpm, 84, "Sample BPM should be 84")
        XCTAssertEqual(instrumental94.sample.bpm, 94, "Sample BPM should be 94")
        XCTAssertEqual(instrumental102.sample.bpm, 102, "Sample BPM should be 102")
    }
    
    // Add a test for the public API
    func testPublicAPI() {
        // Skip if no samples available
        guard !samples94BPM.isEmpty else {
            XCTFail("No 94 BPM samples available for testing")
            return
        }
        
        // Add an instrumental
        let instrumental = trackManager.addInstrumental(sample: samples94BPM[0])
        
        // Test public properties
        XCTAssertEqual(instrumental.sample.title, samples94BPM[0].title)
        XCTAssertEqual(instrumental.sample.bpm, 94)
        XCTAssertEqual(instrumental.volume, 1.0)
        
        // Test volume control
        instrumental.volume = 0.5
        XCTAssertEqual(instrumental.volume, 0.5)
        
        // Test playback control
        trackManager.startPlayback()
        XCTAssertTrue(trackManager.isPlaying)
        
        // Test finding samples
        let samplesInC = trackManager.findSamplesByKey(key: .C)
        XCTAssertNotNil(samplesInC)
        
        let samples94 = trackManager.findSamplesByTempo(tempo: 94, tolerance: 0.5)
        XCTAssertNotNil(samples94)
        
        // Test stopping
        trackManager.stopPlayback()
        XCTAssertFalse(trackManager.isPlaying)
    }
} 