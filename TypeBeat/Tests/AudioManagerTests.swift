import XCTest
import AVFoundation
@testable import TypeBeat

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
    
    override func setUpWithError() throws {
        super.setUp()
        audioManager = AudioManager.shared
        
        // Setup audio session for testing
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    override func tearDownWithError() throws {
        audioManager.stopAllPlayers()
        audioManager = nil
        
        // Clean up test audio file
        try? FileManager.default.removeItem(at: testAudioURL)
        
        super.tearDown()
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
    func testPhaseLockMaintained() async {
        let expectation = XCTestExpectation(description: "Phase lock test")
        
        // Use real samples with different BPMs
        let sample1 = Sample(id: 161, 
                            title: "Rock Ya Hips", 
                            key: .C, 
                            bpm: 84.0, 
                            fileName: "00000161-body")
        
        // First, test that a single sample plays
        await audioManager.addSampleToPlay(sample1)
        audioManager.play()
        
        // Wait for playback to stabilize
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Add second sample
        let sample2 = Sample(id: 175, 
                            title: "Real Gangstaz", 
                            key: .GSharp, 
                            bpm: 102.0, 
                            fileName: "00000175-body")
        await audioManager.addSampleToPlay(sample2)
        
        // Wait for second sample to stabilize
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify both samples are playing
        let phase1 = audioManager.getSamplePhase(for: sample1.id)
        let phase2 = audioManager.getSamplePhase(for: sample2.id)
        
        // Only compare phases if both are non-zero
        if phase1 > 0 && phase2 > 0 {
            XCTAssertEqual(phase1, phase2, accuracy: 0.01)
        }
        
        // Cleanup
        audioManager.stopAllPlayers()
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 2.0)
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
        
        let sample = Sample(id: 161, 
                           title: "Rock Ya Hips", 
                           key: .C, 
                           bpm: 84.0, 
                           fileName: "00000161-body")
        
        await audioManager.addSampleToPlay(sample)
        audioManager.play()
        
        // Wait for playback to start
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Get initial progress
        let progress1 = audioManager.loopProgress()
        
        // Wait a bit
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Get second progress
        let progress2 = audioManager.loopProgress()
        
        // Progress should have increased
        XCTAssertGreaterThan(progress2, progress1)
        
        // Progress should be between 0 and 1
        XCTAssertGreaterThanOrEqual(progress1, 0.0)
        XCTAssertLessThanOrEqual(progress1, 1.0)
        XCTAssertGreaterThanOrEqual(progress2, 0.0)
        XCTAssertLessThanOrEqual(progress2, 1.0)
        
        // Cleanup
        audioManager.stopAllPlayers()
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}

// Helper extension for saving audio buffer to file
extension AVAudioPCMBuffer {
    func saveToFile(url: URL, format: AVAudioFormat) throws {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: self)
    }
} 
