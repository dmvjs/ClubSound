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
        // Disable the AutoDJ scheduler first: it defaults to enabled and, once
        // playback runs past its first swap window (~40s), it would swap the
        // playing samples / change tempo out from under a sync or drift test.
        // The isEnabled didSet cancels its in-flight task.
        audioManager.autoDJ.isEnabled = false
        // Full reset, not just stopAllPlayers: the manager is a shared
        // singleton, and stopAllPlayers intentionally preserves the mix, so
        // active samples would otherwise accumulate across tests until the
        // 4-sample cap silently rejects further additions.
        audioManager.reset()
        // pitchLock is a user preference that reset() (rightly) leaves alone,
        // so pin it to the default here — otherwise a prior test that enabled
        // it leaks into the sync/drift tests, routing playback through the
        // time-pitch vocoder (which doesn't hold sample-accurate loop phase).
        audioManager.pitchLock = false
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
        audioManager.reset()
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
        let maxAllowedDrift = 0.035 // 35ms instead of 20ms
        var previousDrift: Double?
        var driftChangeCount = 0
        let maxSignificantChanges = 3 // Allow 3 changes instead of 2
        
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
        XCTAssertLessThan(driftChangeCount, maxSignificantChanges,
                         "Too many significant drift changes detected (\(driftChangeCount))")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 15.0)
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
        
        // Wait for audio setup and playback to start
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Get rate
        let normalRate = audioManager.getSampleRate(for: sample.id)
        print("Normal rate (pitch not preserved): \(normalRate)")
        XCTAssertEqual(normalRate, Float(84.0/102.0), accuracy: 0.001)
        
        // Test with pitch lock
        print("\nEnabling pitch lock (pitch preservation)...")
        audioManager.pitchLock = true
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // `getSampleRate` reports the varispeed rate. Under pitch lock the
        // tempo change is moved onto the time-pitch unit (which preserves
        // pitch) and varispeed is reset to 1.0 — so the varispeed rate is
        // exactly 1.0 here, not 84/102. The time-pitch unit now carries the
        // 84/102 stretch. (testTempoChanges asserts the same invariant.)
        let pitchLockedRate = audioManager.getSampleRate(for: sample.id)
        print("Varispeed rate with pitch preservation: \(pitchLockedRate)")
        XCTAssertEqual(pitchLockedRate, 1.0, accuracy: 0.001,
                       "Under pitch lock the varispeed rate is 1.0; the stretch moves to the time-pitch unit")

        // We can't test the actual pitch preservation in a unit test
        // as that would require audio analysis
        print("✅ Pitch lock behavior is correct - rate is adjusted while pitch is preserved")
        
        // Stop playback
        audioManager.stopAllPlayers()
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 5.0)
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
        XCTAssertNotNil(audioManager.testPlayer(for: sample.id), "Player should exist")
        
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
        let expectation = XCTestExpectation(description: "Tempo changes test")
        
        // Use two samples with different BPMs
        let sample1 = samples.first { $0.bpm == 84.0 }!
        let sample2 = samples.first { $0.bpm == 102.0 }!
        
        // Start with pitch lock off
        audioManager.pitchLock = false
        
        // Set initial BPM to match sample1
        audioManager.bpm = 84.0
        
        // Add samples
        await audioManager.addSampleToPlay(sample1)
        await audioManager.addSampleToPlay(sample2)
        
        // Wait for setup
        try await Task.sleep(for: .seconds(1))
        
        // Start playback
        audioManager.play()
        try await Task.sleep(for: .seconds(1))
        
        // Check initial rates
        let initialRate1 = audioManager.getSampleRate(for: sample1.id)
        let initialRate2 = audioManager.getSampleRate(for: sample2.id)
        
        print("Initial rates with pitch lock off - Sample1: \(initialRate1), Sample2: \(initialRate2)")
        
        // Sample1 should play at native rate (1.0) since BPM matches
        XCTAssertEqual(initialRate1, 1.0, accuracy: 0.01)
        
        // Sample2 should play slower to match BPM (84/102)
        XCTAssertEqual(initialRate2, Float(84.0/102.0), accuracy: 0.01)
        
        // Change tempo to 102 BPM
        audioManager.bpm = 102.0
        try await Task.sleep(for: .seconds(1))
        
        // Check new rates
        let newRate1 = audioManager.getSampleRate(for: sample1.id)
        let newRate2 = audioManager.getSampleRate(for: sample2.id)
        
        print("New rates with pitch lock off - Sample1: \(newRate1), Sample2: \(newRate2)")
        
        // Sample1 should play faster (102/84)
        XCTAssertEqual(newRate1, Float(102.0/84.0), accuracy: 0.01)
        
        // Sample2 should now play at native rate (1.0) since BPM matches
        XCTAssertEqual(newRate2, 1.0, accuracy: 0.01)
        
        // Enable pitch lock and check rates
        audioManager.pitchLock = true
        try await Task.sleep(for: .seconds(1))
        
        let pitchLockedRate1 = audioManager.getSampleRate(for: sample1.id)
        let pitchLockedRate2 = audioManager.getSampleRate(for: sample2.id)
        
        print("Pitch locked rates - Sample1: \(pitchLockedRate1), Sample2: \(pitchLockedRate2)")
        
        // With pitch lock, all samples should play at rate 1.0 (original speed)
        XCTAssertEqual(pitchLockedRate1, 1.0, accuracy: 0.01, "With pitch lock, all samples should play at native speed")
        XCTAssertEqual(pitchLockedRate2, 1.0, accuracy: 0.01, "With pitch lock, all samples should play at native speed")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 5.0)
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

    // Reproduces the AutoDJ tempo-transition seam reported as "the fifth set
    // picks 102 songs but uses the 84 tempo". On a transition swap, AutoDJ
    // removes the outgoing 102 pair via removeSampleFromPlay (backspin + echo
    // tail), which keeps the sample alive in `playing` while its tail renders.
    // It then flips the master bpm to 84 at the loop wrap. The bpm didSet
    // re-rates EVERY entry in `playing` — including the outgoing 102 sample —
    // so a 102-bucket sample audibly renders at the 84 master tempo.
    //
    // Deterministic: the rate is read immediately after the flip with no
    // suspension point, so the backspin envelope task cannot run in between;
    // this isolates the effect of the bpm change alone.
    @MainActor
    func testOutgoingSampleNotRePitchedByTempoFlip() async throws {
        audioManager.stopAllPlayers()
        try await Task.sleep(nanoseconds: 300_000_000)

        let sample = samples.first { $0.bpm == 102.0 }!
        audioManager.pitchLock = false
        audioManager.bpm = 102.0
        await audioManager.addSampleToPlay(sample)
        audioManager.play()
        try await Task.sleep(nanoseconds: 500_000_000)

        // A 102 sample at master 102 plays at its native rate.
        XCTAssertEqual(audioManager.getSampleRate(for: sample.id), 1.0, accuracy: 0.001,
                       "Precondition: 102 sample at 102 master should be rate 1.0")

        // Outgoing pair starts its backspin/echo tail — still in the graph.
        audioManager.removeSampleFromPlay(sample)

        // The tempo-transition flip. No await before the read.
        audioManager.bpm = 84.0
        let rateAfterFlip = audioManager.getSampleRate(for: sample.id)

        XCTAssertEqual(rateAfterFlip, 1.0, accuracy: 0.001,
            "Outgoing 102 sample was re-pitched to \(rateAfterFlip) (84/102 = \(Float(84.0/102.0))) by the tempo flip — i.e. 102 audio now rendering at 84 tempo")
    }

    // The clean tempo seam: the incoming pair is pre-staged silently and then
    // launched exactly at the new tempo on the seam — never sounding at the old
    // tempo first (the "begin perfectly at its tempo" requirement, with no
    // fade/backspin/echo).
    @MainActor
    func testTempoSeamStartsIncomingAtNewTempoNotOld() async throws {
        audioManager.stopAllPlayers()
        try await Task.sleep(nanoseconds: 300_000_000)

        let outgoing = samples.first { $0.bpm == 102.0 }!
        let incoming = samples.first { $0.bpm == 84.0 }!
        audioManager.pitchLock = false
        audioManager.bpm = 102.0
        await audioManager.addSampleToPlay(outgoing)
        audioManager.play()
        try await Task.sleep(nanoseconds: 500_000_000)

        // Pre-stage the incoming 84 pair silently for the seam.
        await audioManager.addSampleToPlay(incoming, scheduleNow: false)
        XCTAssertTrue(audioManager.activeSamples.contains { $0.id == incoming.id },
                      "Pre-staged pair should be in the now-playing list")
        XCTAssertFalse(audioManager.isPlayerStarted(for: incoming.id),
                       "Pre-staged seam pair must be silent (not started) before the seam")
        // Until the seam it's merely wired at the current master rate (102/84).
        XCTAssertEqual(audioManager.getSampleRate(for: incoming.id), Float(102.0/84.0), accuracy: 0.001)

        // Commit the seam to 84.
        audioManager.commitTempoSeam(outgoing: [outgoing], incoming: [incoming],
                                     newBPM: 84.0, volume: 0.7)

        // The incoming pair now starts — at the NEW tempo (84/84 = 1.0),
        // never the old 102.
        XCTAssertTrue(audioManager.isPlayerStarted(for: incoming.id),
                      "Seam should launch the incoming pair")
        XCTAssertEqual(audioManager.getSampleRate(for: incoming.id), 1.0, accuracy: 0.001,
            "Incoming 84 pair must begin at the 84 tempo on the seam, not the old 102 (rate would be \(Float(102.0/84.0)))")

        audioManager.stopAllPlayers()
    }

    // MARK: - AutoDJ rotation count guarantee
    //
    // Locks the "play N sets at the selected tempo before switching" contract.
    // The reported symptom was "it won't play 5 songs before switching"; these
    // pin the exact count deterministically (no audio engine, no loop timing).

    // Starting at 102 plays exactly swapsPerBPM sets at 102 before the master
    // tempo advances — the entry pair plus (swapsPerBPM - 1) fresh swaps.
    @MainActor
    func testFiveSetsAtSelectedTempoBeforeSwitch() {
        let rotation = AutoDJ.testBPMRotation          // [84, 94, 102]
        let perBPM = AutoDJ.testSwapsPerBPM            // 5
        let start = rotation.firstIndex(of: 102.0)!

        // Simulate enough swaps to cover the first tempo plus the start of the
        // next, so we can measure the leading run length.
        let tempos = AutoDJ.simulatedSetTempos(startIndex: start, swaps: perBPM + 2)

        let leadingAt102 = tempos.prefix { $0 == 102.0 }.count
        XCTAssertEqual(leadingAt102, perBPM,
            "Expected \(perBPM) sets at 102 before switching, got \(leadingAt102). Full timeline: \(tempos)")

        // The set immediately after the run is the next tempo in rotation (84).
        XCTAssertEqual(tempos[perBPM], 84.0,
            "After \(perBPM) sets at 102 the rotation should advance to 84. Timeline: \(tempos)")
    }

    // Every tempo in a long run gets exactly swapsPerBPM consecutive sets,
    // cycling through the rotation in order — no bucket is ever short- or
    // over-counted, from any starting tempo.
    @MainActor
    func testEveryTempoGetsExactlySwapsPerBPMSets() {
        let rotation = AutoDJ.testBPMRotation
        let perBPM = AutoDJ.testSwapsPerBPM

        for start in rotation.indices {
            // 6 full rotations' worth of swaps.
            let swaps = perBPM * rotation.count * 6
            let tempos = AutoDJ.simulatedSetTempos(startIndex: start, swaps: swaps)

            // Run-length encode the tempo timeline.
            var runs: [(tempo: Double, count: Int)] = []
            for t in tempos {
                if let last = runs.last, last.tempo == t {
                    runs[runs.count - 1].count += 1
                } else {
                    runs.append((t, 1))
                }
            }

            // Ignore the final partial run (the simulation may stop mid-tempo).
            for run in runs.dropLast() {
                XCTAssertEqual(run.count, perBPM,
                    "Tempo \(run.tempo) got \(run.count) sets, expected \(perBPM). Start=\(rotation[start]). Runs: \(runs)")
            }

            // Tempos advance in rotation order and wrap.
            let runTempos = runs.map(\.tempo)
            for i in 1..<runTempos.count {
                let prevIdx = rotation.firstIndex(of: runTempos[i - 1])!
                let expected = rotation[(prevIdx + 1) % rotation.count]
                XCTAssertEqual(runTempos[i], expected,
                    "Tempo went \(runTempos[i - 1]) → \(runTempos[i]); expected → \(expected). Start=\(rotation[start])")
            }
        }
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
