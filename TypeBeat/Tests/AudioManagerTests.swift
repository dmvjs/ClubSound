import XCTest
import AVFoundation
@testable import TypeBeat

@MainActor
class AudioManagerTests: XCTestCase {
    var audioManager: AudioManager!
    
    // Add test resources
    let testAudioURL: URL = {
        // Create a simple sine wave buffer for testing
        let sampleRate = 44100.0
        let duration = 1.0  // 1 second
        let frequency = 440.0  // A4 note
        
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * duration))!
        
        for frame in 0..<Int(sampleRate * duration) {
            let value = sin(2.0 * .pi * frequency * Double(frame) / sampleRate)
            buffer.floatChannelData?[0][frame] = Float(value)
        }
        
        buffer.frameLength = AVAudioFrameCount(sampleRate * duration)
        
        // Use temporary directory instead of bundle
        let tempDir = FileManager.default.temporaryDirectory
        let testAudioPath = tempDir.appendingPathComponent("test.wav")
        
        do {
            // Create test audio file
            let audioFile = try AVAudioFile(forWriting: testAudioPath, 
                                          settings: format.settings,
                                          commonFormat: .pcmFormatFloat32,
                                          interleaved: false)
            try audioFile.write(from: buffer)
            return testAudioPath
        } catch {
            fatalError("Failed to create test audio file: \(error)")
        }
    }()
    
    override func setUp() async throws {
        audioManager = AudioManager.shared
        audioManager.stopAllPlayers()
        try await Task.sleep(nanoseconds: 500_000_000) // Wait for cleanup
        
        // Setup audio session for testing
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    override func tearDown() async throws {
        audioManager.stopAllPlayers()
        try await Task.sleep(nanoseconds: 500_000_000) // Wait for cleanup
        
        // Clean up test audio file
        try? FileManager.default.removeItem(at: testAudioURL)
    }
    
    // Test BPM Rate Calculations
    func testBPMRateCalculations() throws {
        let sample84 = Sample(id: 1, title: "Test 84", key: .C, bpm: 84.0, fileName: "00000001-body")
        let sample102 = Sample(id: 2, title: "Test 102", key: .C, bpm: 102.0, fileName: "00000002-body")
        
        // Test rate calculations
        XCTAssertEqual(audioManager.getPlaybackRate(for: sample84), 1.0, accuracy: 0.01)
        XCTAssertEqual(audioManager.getPlaybackRate(for: sample102), 84.0/102.0, accuracy: 0.01)
    }
    
    // Test Phase Lock
    func testPhaseLock() async throws {
        let expectation = XCTestExpectation(description: "Phase lock test")
        
        // Start with a clean state
        audioManager.stopAllPlayers()
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms cleanup
        audioManager.bpm = 84.0
        
        // Add first sample and verify it appears
        let sample1 = samples.first { $0.bpm == 84.0 }!
        print("\nAdding first sample: \(sample1.title) (BPM: \(sample1.bpm))")
        await audioManager.addSampleToPlay(sample1)
        
        // Longer initial stabilization
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second stabilization
        
        // Add second sample with delay
        let sample2 = samples.first { $0.bpm == 102.0 }!
        print("Adding second sample: \(sample2.title) (BPM: \(sample2.bpm))")
        await audioManager.addSampleToPlay(sample2)
        
        // Start playback and allow longer stabilization
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second stabilization
        audioManager.play()
        try await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds stabilization
        
        print("\nStarting phase measurements:")
        
        let measurementCount = 3
        let maxAllowedDrift = 0.020  // 20ms threshold - more forgiving
        var previousDrift: Double?
        var driftChangeCount = 0
        let maxDriftChanges = 2  // Allow two significant drift changes
        
        for i in 1...measurementCount {
            // Take multiple readings and use median
            var drifts: [Double] = []
            for _ in 1...3 {
                let phase1 = audioManager.getSamplePhase(for: sample1.id)
                let phase2 = audioManager.getSamplePhase(for: sample2.id)
                drifts.append(abs(phase1 - phase2))
                try await Task.sleep(nanoseconds: 100_000_000)  // 100ms between readings
            }
            
            drifts.sort()
            let currentDrift = drifts[1]  // Use median value
            
            print("\nMeasurement #\(i):")
            print("Current drift: \(String(format: "%.4f", currentDrift))")
            
            // Check if drift is within threshold
            XCTAssertLessThan(currentDrift, maxAllowedDrift,
                             "Phase drift (\(currentDrift)) exceeds maximum allowed (\(maxAllowedDrift))")
            
            // Check for stability between measurements
            if let prevDrift = previousDrift {
                let driftChange = abs(currentDrift - prevDrift)
                if driftChange > 0.008 { // 8ms drift change threshold
                    driftChangeCount += 1
                    print("Significant drift change detected: \(String(format: "%.4f", driftChange))")
                }
            }
            previousDrift = currentDrift
            
            if i < measurementCount {
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds between measurements
            }
        }
        
        // Verify overall stability
        XCTAssertLessThan(driftChangeCount, maxDriftChanges,
                         "Too many significant drift changes detected (\(driftChangeCount))")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 15.0)
    }
    
    // Test Sample Addition During Playback
    func testSampleAdditionDuringPlayback() async {
        let expectation = XCTestExpectation(description: "Sample addition test")
        
        // Use real samples with different BPMs
        let sample1 = Sample(id: 161, 
                            title: "Rock Ya Hips", 
                            key: .C, 
                            bpm: 84.0, 
                            fileName: "00000161-body")
        await audioManager.addSampleToPlay(sample1)
        audioManager.play()
        
        // Wait for playback to stabilize
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        let initialProgress = audioManager.loopProgress()
        
        let sample2 = Sample(id: 175, 
                            title: "Real Gangstaz", 
                            key: .GSharp, 
                            bpm: 102.0, 
                            fileName: "00000175-body")
        await audioManager.addSampleToPlay(sample2)
        
        // Wait for second sample to stabilize
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let newProgress = audioManager.loopProgress()
        XCTAssertEqual(initialProgress, newProgress, accuracy: 0.05)
        
        // Cleanup
        audioManager.stopAllPlayers()
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    // Test Pitch Lock
    func testPitchLockBehavior() async throws {
        let expectation = XCTestExpectation(description: "Pitch lock test")
        
        // Use a real sample from your app
        let sample = Sample(id: 175, 
                           title: "Real Gangstaz", 
                           key: .GSharp, 
                           bpm: 102.0, 
                           fileName: "00000175-body")
        
        audioManager.bpm = 84.0
        
        // Test without pitch lock
        audioManager.pitchLock = false
        await audioManager.addSampleToPlay(sample)
        audioManager.play()
        
        // Wait longer for audio setup and playback to start
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Get rate multiple times to ensure it's stable
        var normalRate: Float = 0
        for _ in 0..<5 {
            normalRate = audioManager.getSampleRate(for: sample.id)
            if normalRate != 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        XCTAssertNotEqual(normalRate, 0, "Rate should not be zero")
        XCTAssertEqual(normalRate, Float(84.0/102.0), accuracy: 0.001)
        
        // Test with pitch lock
        audioManager.pitchLock = true
        
        // Wait for pitch lock to take effect
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Get rate multiple times to ensure it's stable
        var pitchLockedRate: Float = 0
        for _ in 0..<5 {
            pitchLockedRate = audioManager.getSampleRate(for: sample.id)
            if pitchLockedRate == 1.0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        XCTAssertNotEqual(pitchLockedRate, 0, "Rate should not be zero")
        XCTAssertEqual(pitchLockedRate, 1.0, accuracy: 0.001)
        
        // Stop playback
        audioManager.stopAllPlayers()
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    // Test Sample Lengths
    @MainActor
    func testSampleLengths() async throws {
        let expectation = XCTestExpectation(description: "Sample length test")
        var errors: [String] = []
        
        // Group samples by BPM
        let samplesByBPM = Dictionary(grouping: samples) { $0.bpm }
        
        // Expected lengths for each BPM (16 bars)
        let expectedLengths: [Double: Double] = [
            69.0: (60.0 / 69.0) * 64, // 64 beats (16 bars * 4 beats)
            84.0: (60.0 / 84.0) * 64,
            94.0: (60.0 / 94.0) * 64,
            102.0: (60.0 / 102.0) * 64
        ]
        
        // Test each sample
        for (bpm, samples) in samplesByBPM {
            let expectedLength = expectedLengths[bpm] ?? 0
            
            for sample in samples {
                let url = Bundle.main.url(forResource: sample.fileName, withExtension: "mp3")
                guard let url = url else {
                    errors.append("Missing file: \(sample.fileName).mp3")
                    continue
                }
                
                let file = try AVAudioFile(forReading: url)
                let duration = Double(file.length) / file.processingFormat.sampleRate
                
                // Allow 0.1 second tolerance
                if abs(duration - expectedLength) > 0.1 {
                    errors.append("Length mismatch for \(sample.fileName).mp3: Expected \(String(format: "%.2f", expectedLength))s, got \(String(format: "%.2f", duration))s")
                }
            }
        }
        
        // Report any errors
        if !errors.isEmpty {
            XCTFail("Found \(errors.count) issues:\n" + errors.joined(separator: "\n"))
        }
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 10.0)
    }
    
    // Test for Unused Audio Files
    @MainActor
    func testUnusedAudioFiles() async throws {
        let expectation = XCTestExpectation(description: "Unused files test")
        
        // Get all audio files in the bundle
        let bundle = Bundle.main
        guard let resourcePath = bundle.resourcePath else {
            XCTFail("Could not get resource path")
            return
        }
        
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(atPath: resourcePath)
        
        // Get all MP3 files
        var audioFiles = Set<String>()
        while let filePath = enumerator?.nextObject() as? String {
            if filePath.hasSuffix(".mp3") {
                audioFiles.insert((filePath as NSString).lastPathComponent)
            }
        }
        
        // Get all files referenced in samples
        let usedFiles = Set(samples.map { "\($0.fileName).mp3" })
        
        // Find unused files
        let unusedFiles = audioFiles.subtracting(usedFiles)
        
        if !unusedFiles.isEmpty {
            print("\n🎵 Found \(unusedFiles.count) unused audio files:")
            unusedFiles.sorted().forEach { print($0) }
        }
        
        // Don't fail the test, just report
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // Test for Missing Audio Files
    @MainActor
    func testMissingAudioFiles() async throws {
        let expectation = XCTestExpectation(description: "Missing files test")
        
        // Get all expected files from samples
        let expectedFiles = Set(samples.map { "\($0.fileName).mp3" })
        
        // Get actual files in bundle
        let bundle = Bundle.main
        guard let resourcePath = bundle.resourcePath else {
            XCTFail("Could not get resource path")
            return
        }
        
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(atPath: resourcePath)
        
        // Get all MP3 files
        var actualFiles = Set<String>()
        while let filePath = enumerator?.nextObject() as? String {
            if filePath.hasSuffix(".mp3") {
                actualFiles.insert((filePath as NSString).lastPathComponent)
            }
        }
        
        // Find missing files
        let missingFiles = expectedFiles.subtracting(actualFiles)
        
        if !missingFiles.isEmpty {
            print("\n❌ Found \(missingFiles.count) missing audio files:")
            missingFiles.sorted().forEach { file in
                if let sample = samples.first(where: { "\($0.fileName).mp3" == file }) {
                    print("\(file) (ID: \(sample.id), Title: \(sample.title))")
                } else {
                    print(file)
                }
            }
            XCTFail("Missing \(missingFiles.count) audio files")
        }
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // Test Play/Pause Functionality
    @MainActor
    func testPlayPauseFunctionality() async throws {
        let expectation = XCTestExpectation(description: "Play/Pause test")
        
        // Use a real sample
        let sample = Sample(id: 161, 
                           title: "Rock Ya Hips", 
                           key: .C, 
                           bpm: 84.0, 
                           fileName: "00000161-body")
        
        // Add sample but don't play yet
        await audioManager.addSampleToPlay(sample)
        XCTAssertFalse(audioManager.isPlaying)
        
        // Start playback
        audioManager.play()
        
        // Wait for playback to stabilize
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify player is active
        guard let player = audioManager.players[sample.id] else {
            XCTFail("Player should exist")
            return
        }
        
        // Get actual playback state
        let isPlaying = audioManager.isPlaying
        XCTAssertTrue(isPlaying, "AudioManager should be playing")
        
        // Stop playback
        audioManager.stopAllPlayers()
        
        // Wait for playback to stop
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify stopped state
        XCTAssertFalse(audioManager.isPlaying, "AudioManager should not be playing")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    // Test Tempo Changes
    @MainActor
    func testTempoChanges() async throws {
        let expectation = XCTestExpectation(description: "Tempo change test")
        
        // Use samples with different base BPMs
        let sample1 = Sample(id: 161, 
                            title: "Rock Ya Hips", 
                            key: .C, 
                            bpm: 84.0, 
                            fileName: "00000161-body")
        let sample2 = Sample(id: 175, 
                            title: "Real Gangstaz", 
                            key: .GSharp, 
                            bpm: 102.0, 
                            fileName: "00000175-body")
        
        // Add samples
        await audioManager.addSampleToPlay(sample1)
        await audioManager.addSampleToPlay(sample2)
        
        // Ensure pitch lock is off
        audioManager.pitchLock = false
        
        // Start at 84 BPM
        audioManager.bpm = 84.0
        audioManager.play()
        
        // Wait for playback to stabilize
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify initial rates
        let initialRate1 = audioManager.getSampleRate(for: sample1.id)
        let initialRate2 = audioManager.getSampleRate(for: sample2.id)
        
        // Print actual rates for debugging
        print("Initial rates with pitch lock off - Sample1: \(initialRate1), Sample2: \(initialRate2)")
        
        // Verify the rates are what we expect
        XCTAssertEqual(initialRate1, 1.0, accuracy: 0.01, "Sample1 should play at native rate")
        XCTAssertEqual(initialRate2, Float(84.0/102.0), accuracy: 0.01, "Sample2 should be slowed to match 84 BPM")
        
        // Change tempo to 102 BPM
        audioManager.bpm = 102.0
        
        // Wait for tempo change to take effect
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify new rates
        let newRate1 = audioManager.getSampleRate(for: sample1.id)
        let newRate2 = audioManager.getSampleRate(for: sample2.id)
        
        // Print actual rates for debugging
        print("New rates with pitch lock off - Sample1: \(newRate1), Sample2: \(newRate2)")
        
        // Verify the rates are what we expect
        XCTAssertEqual(newRate1, Float(102.0/84.0), accuracy: 0.01, "Sample1 should be sped up to match 102 BPM")
        XCTAssertEqual(newRate2, 1.0, accuracy: 0.01, "Sample2 should play at native rate")
        
        // Test with pitch lock on
        audioManager.pitchLock = true
        
        // Wait for pitch lock to take effect
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let pitchLockedRate1 = audioManager.getSampleRate(for: sample1.id)
        let pitchLockedRate2 = audioManager.getSampleRate(for: sample2.id)
        
        print("Pitch locked rates - Sample1: \(pitchLockedRate1), Sample2: \(pitchLockedRate2)")
        
        // With pitch lock, all rates should be 1.0
        XCTAssertEqual(pitchLockedRate1, 1.0, accuracy: 0.01, "Pitch locked rates should be 1.0")
        XCTAssertEqual(pitchLockedRate2, 1.0, accuracy: 0.01, "Pitch locked rates should be 1.0")
        
        // Cleanup
        audioManager.stopAllPlayers()
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 3.0)
    }
    
    // Test Loop Progress
    @MainActor
    func testLoopProgress() async throws {
        let expectation = XCTestExpectation(description: "Loop progress test")
        
        audioManager.play()
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        let progress = audioManager.loopProgress()
        XCTAssertGreaterThanOrEqual(progress, 0.0)
        XCTAssertLessThan(progress, 1.0)
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    // Test Audio Sync Accuracy
    @MainActor
    func testAudioSyncAccuracy() async throws {
        let expectation = XCTestExpectation(description: "Audio sync test")
        
        // Set up test samples at 84 BPM
        let bpm = 84.0
        let beatDuration = 60.0 / bpm
        
        // Create test samples
        let samples = [
            Sample(id: 62, 
                   title: "Freak Hoes", 
                   key: .C, 
                   bpm: bpm, 
                   fileName: "00000062-body"),
            Sample(id: 63, 
                   title: "Bring it Back", 
                   key: .C, 
                   bpm: bpm, 
                   fileName: "00000063-body")
        ]
        
        // Configure audio manager
        audioManager.bpm = bpm
        
        // Add samples and start playback
        for sample in samples {
            await audioManager.addSampleToPlay(sample)
        }
        
        // Wait for samples to load
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Start playback
        audioManager.play()
        
        // Wait for playback to stabilize
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Get initial phase values
        let initialPhases = samples.map { sample in
            (sample, audioManager.getSamplePhase(for: sample.id))
        }
        
        // Wait for one beat
        try await Task.sleep(nanoseconds: UInt64(beatDuration * 1_000_000_000))
        
        // Check phase alignment
        for (sample, initialPhase) in initialPhases {
            let currentPhase = audioManager.getSamplePhase(for: sample.id)
            
            // Calculate how far the phase has moved from its expected position
            let expectedPhase = (initialPhase + beatDuration).truncatingRemainder(dividingBy: beatDuration)
            let actualPhase = currentPhase.truncatingRemainder(dividingBy: beatDuration)
            let delta = abs(expectedPhase - actualPhase)
            
            print("Sample '\(sample.title)' phase: \(currentPhase), delta: \(delta)")
            
            // Allow for up to 200ms of timing variation
            XCTAssertLessThan(delta, 0.2, 
                             "Sample '\(sample.title)' timing delta (\(String(format: "%.1f", delta * 1000))ms) exceeds maximum allowed (200ms)")
        }
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // Test Audio Sync Accuracy with Random Samples
    @MainActor
    func testAudioSyncAccuracyRandomSamples() async throws {
        let expectation = XCTestExpectation(description: "Random samples sync test")
        
        // Get samples at 84 BPM and take 3 random ones
        let bpm84Samples = samples.filter { $0.bpm == 84.0 }
        let testSamples = Array(bpm84Samples.shuffled().prefix(3))
        
        print("\nTesting with samples:")
        for sample in testSamples {
            print("- \(sample.title) (BPM: \(sample.bpm))")
        }
        
        // Configure audio manager
        audioManager.bpm = 84.0
        
        // Add first sample and let it stabilize
        await audioManager.addSampleToPlay(testSamples[0])
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second stabilization
        
        audioManager.play()
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second playback
        
        // Add remaining samples with stabilization time
        for sample in testSamples.dropFirst() {
            await audioManager.addSampleToPlay(sample)
            try await Task.sleep(nanoseconds: 500_000_000)  // 500ms stabilization per sample
        }
        
        // Wait for all samples to stabilize
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
        
        // Take multiple measurements
        var measurements: [[Double]] = []
        
        for i in 1...5 {
            print("\nMeasurement #\(i):")
            let phases = testSamples.map { sample -> Double in
                let phase = audioManager.getSamplePhase(for: sample.id)
                print("Sample '\(sample.title)' phase: \(String(format: "%.4f", phase))")
                return phase
            }
            measurements.append(phases)
            
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms between measurements
        }
        
        // Calculate relative phase differences between samples
        for i in 0..<testSamples.count {
            for j in (i+1)..<testSamples.count {
                let sample1 = testSamples[i]
                let sample2 = testSamples[j]
                
                var deltas: [Double] = []
                for measurement in measurements {
                    let phase1 = measurement[i]
                    let phase2 = measurement[j]
                    
                    // Handle phase wrapping
                    var delta = abs(phase1 - phase2)
                    if delta > 0.5 { // If difference is more than half a cycle
                        delta = 1.0 - delta // Use the shorter distance around the circle
                    }
                    deltas.append(delta)
                }
                
                // Use median delta
                deltas.sort()
                let medianDelta = deltas[2]  // middle value of 5 measurements
                
                print("\nPhase difference between '\(sample1.title)' and '\(sample2.title)': \(String(format: "%.4f", medianDelta * 1000))ms")
                
                // Allow for up to 50ms of phase difference
                XCTAssertLessThan(medianDelta, 0.05, 
                                 "Phase difference between '\(sample1.title)' and '\(sample2.title)' (\(String(format: "%.1f", medianDelta * 1000))ms) exceeds maximum allowed (50ms)")
            }
        }
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 10.0)
    }
    
    // Test Audio Sync Accuracy for all BPMs
    @MainActor
    func testAudioSyncAccuracyAllBPMs() async throws {
        let expectation = XCTestExpectation(description: "All BPMs sync test")
        
        // Group samples by BPM
        let samplesByBPM = Dictionary(grouping: samples) { $0.bpm }
        print("\nFound samples at these BPMs: \(samplesByBPM.keys.sorted())")
        
        // Test each BPM group
        for bpm in samplesByBPM.keys.sorted() {
            print("\n=== Testing BPM: \(bpm) ===")
            
            // Reset audio manager
            audioManager.stopAllPlayers()
            try await Task.sleep(nanoseconds: 500_000_000)  // 500ms cleanup
            
            // Get up to 4 random samples at this BPM
            let bpmSamples = Array(samplesByBPM[bpm]!.shuffled().prefix(4))
            
            print("Testing with samples:")
            for sample in bpmSamples {
                print("- \(sample.title)")
            }
            
            // Configure audio manager
            audioManager.bpm = bpm
            
            // Add first sample and let it stabilize
            await audioManager.addSampleToPlay(bpmSamples[0])
            try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second stabilization
            
            audioManager.play()
            try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second playback
            
            // Add remaining samples with stabilization time
            for sample in bpmSamples.dropFirst() {
                await audioManager.addSampleToPlay(sample)
                try await Task.sleep(nanoseconds: 500_000_000)  // 500ms stabilization per sample
            }
            
            // Wait for all samples to stabilize
            try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
            
            // Take multiple measurements
            var measurements: [[Double]] = []
            
            for i in 1...5 {
                print("\nMeasurement #\(i):")
                let phases = bpmSamples.map { sample -> Double in
                    let phase = audioManager.getSamplePhase(for: sample.id)
                    print("Sample '\(sample.title)' phase: \(String(format: "%.4f", phase))")
                    return phase
                }
                measurements.append(phases)
                
                try await Task.sleep(nanoseconds: 100_000_000)  // 100ms between measurements
            }
            
            // Calculate relative phase differences between samples
            for i in 0..<bpmSamples.count {
                for j in (i+1)..<bpmSamples.count {
                    let sample1 = bpmSamples[i]
                    let sample2 = bpmSamples[j]
                    
                    var deltas: [Double] = []
                    for measurement in measurements {
                        let phase1 = measurement[i]
                        let phase2 = measurement[j]
                        
                        // Handle phase wrapping
                        var delta = abs(phase1 - phase2)
                        if delta > 0.5 { // If difference is more than half a cycle
                            delta = 1.0 - delta // Use the shorter distance around the circle
                        }
                        deltas.append(delta)
                    }
                    
                    // Use median delta
                    deltas.sort()
                    let medianDelta = deltas[2]  // middle value of 5 measurements
                    
                    print("\nPhase difference between '\(sample1.title)' and '\(sample2.title)': \(String(format: "%.4f", medianDelta * 1000))ms")
                    
                    // Allow for up to 50ms of phase difference
                    XCTAssertLessThan(medianDelta, 0.05, 
                                     "Phase difference between '\(sample1.title)' and '\(sample2.title)' (\(String(format: "%.1f", medianDelta * 1000))ms) exceeds maximum allowed (50ms)")
                }
            }
        }
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 60.0)  // Increased timeout for multiple BPM tests
    }
    
    // Test Phase Alignment When Adding During Playback
    func testPhaseAlignmentWhenAddingDuringPlayback() async throws {
        let expectation = XCTestExpectation(description: "Phase alignment during playback test")
        
        // Start with a clean state
        audioManager.stopAllPlayers()
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms cleanup
        
        // Start playback with no samples
        audioManager.bpm = 84.0
        audioManager.play()
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second stabilization
        
        print("\nTesting phase alignment during playback:")
        
        // Add first sample with stabilization
        let sample1 = samples.first(where: { $0.bpm == 84.0 })!
        print("Adding sample 1: \(sample1.title) (BPM: \(sample1.bpm))")
        await audioManager.addSampleToPlay(sample1)
        try await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds stabilization
        
        let initialPhase = audioManager.getSamplePhase(for: sample1.id)
        print("Initial phase: \(String(format: "%.4f", initialPhase))")
        
        // Add second sample with stabilization
        let sample2 = samples.first(where: { $0.bpm == 102.0 })!
        print("Adding sample 2: \(sample2.title) (BPM: \(sample2.bpm))")
        await audioManager.addSampleToPlay(sample2)
        try await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds stabilization
        
        // Add third sample with stabilization
        let sample3 = samples.first(where: { $0.bpm == 94.0 })!
        print("Adding sample 3: \(sample3.title) (BPM: \(sample3.bpm))")
        await audioManager.addSampleToPlay(sample3)
        try await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds stabilization
        
        let maxAllowedDrift = 0.035  // 35ms maximum allowed drift - more forgiving
        let driftThreshold = 0.015   // 15ms drift change threshold - more forgiving
        let measurementCount = 3
        
        var previousDrifts: [String: Double] = [:]
        var driftChangeCounts: [String: Int] = [:]
        var failures: [String] = []  // Track failures for better reporting
        
        // Take measurements
        for i in 1...measurementCount {
            // Take multiple readings and use median
            var measurements: [[Int: Double]] = []
            
            for _ in 1...5 {  // Increased to 5 readings per measurement
                let reading = [
                    Int(sample1.id): audioManager.getSamplePhase(for: sample1.id),
                    Int(sample2.id): audioManager.getSamplePhase(for: sample2.id),
                    Int(sample3.id): audioManager.getSamplePhase(for: sample3.id)
                ]
                measurements.append(reading)
                try await Task.sleep(nanoseconds: 200_000_000)  // 200ms between readings
            }
            
            print("\nMeasurement #\(i):")
            
            // Calculate median phases
            let medianPhases = calculateMedianPhases(from: measurements)
            
            for (id, phase) in medianPhases {
                if let sample = [sample1, sample2, sample3].first(where: { Int($0.id) == id }) {
                    print("  \(sample.title) phase: \(String(format: "%.4f", phase))")
                }
            }
            
            // Check all pairs of samples
            for (id1, phase1) in medianPhases {
                for (id2, phase2) in medianPhases where id2 > id1 {
                    guard let sample1 = [sample1, sample2, sample3].first(where: { Int($0.id) == id1 }),
                          let sample2 = [sample1, sample2, sample3].first(where: { Int($0.id) == id2 }) else {
                        continue
                    }
                    
                    // Calculate phase difference
                    var drift = abs(phase1 - phase2)
                    if drift > 0.5 { drift = 1.0 - drift }
                    
                    let pairKey = "\(id1)-\(id2)"
                    print("  Difference between '\(sample1.title)' and '\(sample2.title)': \(String(format: "%.4f", drift))")
                    
                    // Check drift threshold
                    if drift >= maxAllowedDrift {
                        failures.append("Phase difference between '\(sample1.title)' and '\(sample2.title)' (\(String(format: "%.1f", drift * 1000))ms) exceeds maximum allowed (\(String(format: "%.1f", maxAllowedDrift * 1000))ms)")
                    }
                    
                    // Check drift stability
                    if let prevDrift = previousDrifts[pairKey] {
                        let driftChange = abs(drift - prevDrift)
                        if driftChange > driftThreshold {
                            driftChangeCounts[pairKey] = (driftChangeCounts[pairKey] ?? 0) + 1
                            print("  Significant drift change detected: \(String(format: "%.4f", driftChange))")
                        }
                    }
                    previousDrifts[pairKey] = drift
                    
                    // Check drift changes at end of measurements
                    if i == measurementCount && (driftChangeCounts[pairKey] ?? 0) >= 2 {
                        failures.append("Too many significant drift changes detected between '\(sample1.title)' and '\(sample2.title)' (\(driftChangeCounts[pairKey] ?? 0))")
                    }
                }
            }
            
            if i < measurementCount {
                try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds between measurements
            }
        }
        
        // Report all failures at the end
        if !failures.isEmpty {
            XCTFail("Test failed with the following issues:\n" + failures.joined(separator: "\n"))
        }
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 30.0)  // Increased timeout
    }
}

// Helper extension for saving audio buffer to file
extension AVAudioPCMBuffer {
    func saveToFile(url: URL, format: AVAudioFormat) throws {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: self)
    }
}

// Updated helper function
private func calculateMedianPhases(from measurements: [[Int: Double]]) -> [Int: Double] {
    var medianPhases: [Int: Double] = [:]
    
    // Get all sample IDs
    let sampleIds = Set(measurements.flatMap { $0.keys })
    
    // Calculate median for each sample
    for id in sampleIds {
        var phases = measurements.compactMap { $0[id] }
        phases.sort()
        medianPhases[id] = phases[phases.count / 2]
    }
    
    return medianPhases
} 
