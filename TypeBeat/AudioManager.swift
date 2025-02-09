import Foundation
import AVFoundation
import Combine

class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    @Published var activeSamples: Set<Int> = []
    @Published var bpm: Double = 84.0 {
        didSet {
            restartAllPlayersWithAdjustedPhase()
        }
    }
    
    @Published var pitchLock: Bool = false {
        didSet {
            adjustPlaybackRatesAndKeepPhase()
        }
    }

    @Published var isPlaying: Bool = false
    @Published var isEngineReady: Bool = false
    private var initializationCompletion: (() -> Void)?

    private let engine = AVAudioEngine()
    private var players: [Int: AVAudioPlayerNode] = [:]
    private var mixers: [Int: AVAudioMixerNode] = [:]
    private var varispeedNodes: [Int: AVAudioUnitVarispeed] = [:]
    private var timePitchNodes: [Int: AVAudioUnitTimePitch] = [:]
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var referenceStartTime: AVAudioTime?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // High quality audio session setup
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredIOBufferDuration(0.005)
            try audioSession.setCategory(.playback, mode: .default, options: [
                .mixWithOthers,
                .duckOthers
            ])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        
        // Connect main mixer to output
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        
        // Start engine
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
            return
        }
        
        // Initialize reference time
        referenceStartTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
    }
    
    private func initializeEngine(completion: @escaping () -> Void) async {
        do {
            // Create a test sample with actual audio data
            guard let testUrl = Bundle.main.url(forResource: "00000001-body", withExtension: "mp3") else {
                print("Critical Error: Could not find initialization audio file")
                return
            }
            
            let testFile = try AVAudioFile(forReading: testUrl)
            let format = testFile.processingFormat
            let frameCount = AVAudioFrameCount(testFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                print("Critical Error: Could not create PCM buffer")
                return
            }
            try testFile.read(into: buffer)
            
            // Create and configure test nodes with high-quality settings
            let testPlayer = AVAudioPlayerNode()
            let testMixer = AVAudioMixerNode()
            let testVarispeed = AVAudioUnitVarispeed()
            let testTimePitch = AVAudioUnitTimePitch()
            
            // Configure high-quality audio processing
            testTimePitch.bypass = false
            testTimePitch.overlap = 8.0  // Higher overlap for better quality
            
            // Attach all test nodes
            [testPlayer, testMixer, testVarispeed, testTimePitch].forEach { node in
                engine.attach(node)
            }
            
            // Connect test nodes with explicit format
            let highQualityFormat = AVAudioFormat(standardFormatWithSampleRate: 48000,
                                                channels: 2)
            
            engine.connect(testPlayer, to: testVarispeed, format: format)
            engine.connect(testVarispeed, to: testTimePitch, format: format)
            engine.connect(testTimePitch, to: testMixer, format: format)
            engine.connect(testMixer, to: engine.mainMixerNode, format: highQualityFormat)
            
            // Completely mute the test mixer
            testMixer.outputVolume = 0.0
            engine.mainMixerNode.outputVolume = 0.0  // Double ensure silence
            
            // Start engine with maximum quality settings
            engine.prepare()
            try engine.start()
            
            // Schedule and play test audio with precise timing
            let playbackDuration = 0.5  // Longer test for thorough initialization
            testPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            testPlayer.play()
            
            // Wait for initialization with high-precision timing
            let initializationDuration = UInt32(playbackDuration * 1_000_000)
            usleep(initializationDuration)
            
            // Proper cleanup sequence
            testPlayer.stop()
            engine.pause()
            
            // Detach nodes in reverse order of connection
            [testTimePitch, testVarispeed, testMixer, testPlayer].forEach { node in
                engine.detach(node)
            }
            
            // Reset engine state
            engine.reset()
            
            // Restore main mixer volume
            engine.mainMixerNode.outputVolume = 1.0
            
            // Restart engine for normal operation
            try engine.start()
            initializeReferenceStartTimeIfNeeded()
            
            // Ensure we're on the main thread for the completion
            await MainActor.run {
                completion()
            }
            
        } catch {
            print("Critical Error during audio engine initialization: \(error.localizedDescription)")
            // In a production app, you might want to show a user-facing error here
        }
    }
    
    func loopProgress(for sampleId: Int) -> Double {
        // Return 0 if not playing
        guard isPlaying else { return 0.0 }
        
        guard let startTime = referenceStartTime,
              let renderTime = engine.outputNode.lastRenderTime else { return 0.0 }

        guard renderTime.hostTime >= startTime.hostTime else {
            print("Invalid timing: renderTime.hostTime is less than startTime.hostTime.")
            return 0.0
        }

        let elapsedHostTime = renderTime.hostTime - startTime.hostTime
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)

        let elapsedSeconds = Double(elapsedHostTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom) / Double(NSEC_PER_SEC)

        // 16 bars * 4 beats per bar = 64 beats
        let totalBeats = 16.0 * 4.0  // 64 beats
        let totalDuration = (totalBeats * 60.0) / bpm
        
        let progress = (elapsedSeconds.truncatingRemainder(dividingBy: totalDuration)) / totalDuration
        return progress
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredIOBufferDuration(0.005)
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Error setting up audio session: \(error)")
        }
    }
    
    private func setupEngineNodes() {
        engine.mainMixerNode.volume = 1.0
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
    }
    
    private func calculatePreciseStartTime() -> AVAudioTime {
        let outputLatency = engine.outputNode.presentationLatency
        let currentTime = engine.outputNode.lastRenderTime ?? AVAudioTime(hostTime: mach_absolute_time())
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let currentSample = currentTime.sampleTime
        let samplesPerBeat = sampleRate * (60.0 / bpm)
        
        // Convert to Double for calculation
        let nextBeatSample = ceil(Double(currentSample) / samplesPerBeat) * samplesPerBeat
        
        // Convert back to Int64 for AVAudioTime
        let timeUntilNextBeat = Double(Int64(nextBeatSample) - currentSample) / sampleRate
        
        // Add a small buffer for scheduling (2 ms)
        let schedulingBuffer = 0.002
        
        // Convert to host time
        let hostTimePerSecond = Double(NSEC_PER_SEC)
        let futureHostTime = currentTime.hostTime + UInt64(hostTimePerSecond * (timeUntilNextBeat + schedulingBuffer - outputLatency))
        
        return AVAudioTime(hostTime: futureHostTime)
    }
    
    func addSampleToPlay(_ sample: Sample) {
        guard !activeSamples.contains(sample.id) else { return }
        
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()
        let varispeed = AVAudioUnitVarispeed()
        let timePitch = AVAudioUnitTimePitch()

        engine.attach(player)
        engine.attach(varispeed)
        engine.attach(timePitch)
        engine.attach(mixer)

        guard let url = Bundle.main.url(forResource: sample.fileName, withExtension: "mp3") else {
            print("Could not find file \(sample.fileName)")
            return
        }

        do {
            let file = try AVAudioFile(forReading: url)
            let processingFormat = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else { return }
            try file.read(into: buffer)
            buffers[sample.id] = buffer
            
            // Configure high quality nodes
            timePitch.bypass = false
            timePitch.overlap = 8.0  // Higher overlap for better quality pitch shifting
            
            varispeed.bypass = false
            
            // Use high quality format for all connections
            let highQualityFormat = AVAudioFormat(standardFormatWithSampleRate: 48000,
                                                 channels: 2)
            
            engine.connect(player, to: varispeed, format: highQualityFormat)
            engine.connect(varispeed, to: timePitch, format: highQualityFormat)
            engine.connect(timePitch, to: mixer, format: highQualityFormat)
            engine.connect(mixer, to: engine.mainMixerNode, format: highQualityFormat)

            players[sample.id] = player
            mixers[sample.id] = mixer
            varispeedNodes[sample.id] = varispeed
            timePitchNodes[sample.id] = timePitch
            activeSamples.insert(sample.id)

            adjustPlaybackRates(for: sample)
            mixer.outputVolume = 0.0

            // If this is our first sample while playing, establish reference time
            if isPlaying && referenceStartTime == nil {
                referenceStartTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
            }

            // Always use reference time if playing
            if isPlaying {
                if let startTime = referenceStartTime {
                    player.scheduleBuffer(buffer, at: startTime, options: [.loops, .interruptsAtLoop])
                    player.play(at: startTime)
                }
            } else {
                // If not playing, just schedule but don't play
                if let startTime = referenceStartTime {
                    player.scheduleBuffer(buffer, at: startTime, options: [.loops, .interruptsAtLoop])
                }
            }
        } catch {
            print("Error loading audio file: \(error)")
        }
    }

    func setMasterVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }
    
    func muteAndFadeIn(_ player: AVAudioPlayerNode, fadeDuration: TimeInterval = 0.2) {
        // Mute audio
        player.volume = 0.0

        // Gradually fade in the volume
        let steps = 20
        let fadeStepDuration = fadeDuration / Double(steps)
        let fadeIncrement = 1.0 / Float(steps)

        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeStepDuration * Double(step)) {
                player.volume = Float(step) * fadeIncrement
            }
        }
    }

    private func resetReferenceStartTimeToNearestBeat() {
        guard let referenceTime = referenceStartTime else { return }
        
        let hostTimeNow = mach_absolute_time()
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        
        let elapsedHostTime = Double(hostTimeNow - referenceTime.hostTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
        let elapsedTimeInSeconds = elapsedHostTime / Double(NSEC_PER_SEC)
        
        let beatsPerSecond = bpm / 60.0
        let elapsedBeats = elapsedTimeInSeconds * beatsPerSecond
        let nearestBeatBoundary = round(elapsedBeats) / beatsPerSecond
        
        let nearestBeatOffsetSeconds = nearestBeatBoundary - elapsedTimeInSeconds
        referenceStartTime = AVAudioTime(hostTime: referenceTime.hostTime + secondsToHostTime(nearestBeatOffsetSeconds))
    }

    private func initializeReferenceStartTimeIfNeeded() {
        if referenceStartTime == nil {
            referenceStartTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        }
    }
    
    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            // Establish new reference time when starting playback
            referenceStartTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
            
            // Restart all players with the same reference time
            for (sampleId, player) in players {
                guard let buffer = buffers[sampleId] else { continue }
                player.stop()
                if let startTime = referenceStartTime {
                    player.scheduleBuffer(buffer, at: startTime, options: [.loops, .interruptsAtLoop])
                    player.play(at: startTime)
                }
            }
        } else {
            stopAllPlayers()
        }
    }

    func togglePitchLockWithoutRestart() {
        pitchLock.toggle()
        adjustPlaybackRatesAndKeepPhase()
    }

    private func adjustPlaybackRatesAndKeepPhase() {
        for (sampleId, _) in players {
            if let sample = samples.first(where: { $0.id == sampleId }) {
                adjustPlaybackRates(for: sample)
            }
        }
    }

    private func restartAllPlayersWithAdjustedPhase() {
        let nextBeat = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        referenceStartTime = nextBeat
        
        stopAllPlayers()
        
        for (sampleId, player) in players {
            guard let buffer = buffers[sampleId] else { continue }
            
            if let sample = samples.first(where: { $0.id == sampleId }) {
                adjustPlaybackRates(for: sample)
            }
            
            player.scheduleBuffer(buffer, at: nextBeat, options: [.loops, .interruptsAtLoop])
            player.play(at: nextBeat)
        }
    }

    func removeSampleFromPlay(_ sample: Sample) {
        guard let player = players[sample.id] else { return }

        player.stop()
        engine.detach(player)
        
        if let mixer = mixers[sample.id] {
            engine.detach(mixer)
        }
        if let varispeed = varispeedNodes[sample.id] {
            engine.detach(varispeed)
        }
        if let timePitch = timePitchNodes[sample.id] {
            engine.detach(timePitch)
        }
        
        players.removeValue(forKey: sample.id)
        mixers.removeValue(forKey: sample.id)
        varispeedNodes.removeValue(forKey: sample.id)
        timePitchNodes.removeValue(forKey: sample.id)
        buffers.removeValue(forKey: sample.id)
        activeSamples.remove(sample.id)
    }
    
    func setVolume(for sample: Sample, volume: Float) {
        guard let mixer = mixers[sample.id] else { return }
        mixer.outputVolume = volume
    }
    
    private func adjustPlaybackRates(for sample: Sample) {
        guard let varispeed = varispeedNodes[sample.id],
              let timePitch = timePitchNodes[sample.id] else { return }
        
        let rate = bpm / sample.bpm
        
        if pitchLock {
            varispeed.rate = 1.0
            timePitch.rate = Float(rate)
            timePitch.pitch = 0.0
            // Higher quality settings for pitch-locked mode
            timePitch.overlap = 8.0
        } else {
            varispeed.rate = Float(rate)
            timePitch.rate = 1.0
            timePitch.pitch = 0.0
            // Standard quality for varispeed mode
            timePitch.overlap = 3.0
        }
    }

    private func stopAllPlayers() {
        for player in players.values {
            player.stop()
        }
    }
    
    private func secondsToHostTime(_ seconds: Double) -> UInt64 {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanoSeconds = seconds * Double(NSEC_PER_SEC)
        let hostTicks = nanoSeconds * Double(timebaseInfo.denom) / Double(timebaseInfo.numer)
        return UInt64(hostTicks)
    }

    func stopAllPlayback() {
        // Stop all currently playing samples
        for sample in activeSamples {
            if let player = players[sample] {
                player.stop()
            }
        }
        // Clear active samples
        activeSamples.removeAll()
        // Reset playback state
        isPlaying = false
        engine.stop()
        
        // Clear all players and buffers
        players.removeAll()
        mixers.removeAll()
        varispeedNodes.removeAll()
        timePitchNodes.removeAll()
        buffers.removeAll()
    }

    private func monitorPhaseAlignment() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in  // Check less frequently
            guard let self = self else { return }
            
            let currentTime = self.engine.outputNode.lastRenderTime ?? AVAudioTime(hostTime: mach_absolute_time())
            let sampleRate = self.engine.outputNode.outputFormat(forBus: 0).sampleRate
            let samplesPerBeat = (60.0 / self.bpm) * sampleRate
            
            for (sampleId, player) in self.players {
                guard let playerTime = player.lastRenderTime else { continue }
                
                // Calculate phase difference
                let phaseDiff = Double(playerTime.sampleTime % Int64(samplesPerBeat)) / samplesPerBeat
                
                // Only correct if significantly out of phase (5% threshold instead of 1%)
                if phaseDiff > 0.05 {
                    self.correctPhase(for: sampleId)
                }
            }
        }
    }

    private func correctPhase(for sampleId: Int) {
        guard let player = players[sampleId],
              let buffer = buffers[sampleId] else { return }
        
        // Calculate next beat boundary
        let nextBeatTime = calculatePreciseStartTime()
        
        // Reschedule the player
        player.stop()
        player.scheduleBuffer(buffer, at: nextBeatTime, options: [.loops, .interruptsAtLoop], completionHandler: nil)
        player.play(at: nextBeatTime)
    }

    func updateBPM(to newBPM: Double) {
        // Stop all playback temporarily
        let wasPlaying = isPlaying
        if wasPlaying {
            stopAllPlayers()
        }
        
        // Update BPM
        self.bpm = newBPM
        
        // Adjust rates for all samples
        for (sampleId, _) in players {
            if let sample = samples.first(where: { $0.id == sampleId }) {
                adjustPlaybackRates(for: sample)
            }
        }
        
        // If was playing, restart all players in sync
        if wasPlaying {
            referenceStartTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
            restartAllPlayersWithAdjustedPhase()
        }
    }

    private func loadAudioFile(for sample: Sample) throws -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: sample.fileName, withExtension: "mp3") else {
            print("Could not find audio file: \(sample.fileName)")
            return nil
        }
        
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("Could not create buffer for: \(sample.fileName)")
            return nil
        }
        
        try file.read(into: buffer)
        return buffer
    }

}
