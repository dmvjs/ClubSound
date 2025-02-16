import Foundation
import AVFoundation
import Combine
import SwiftUI

class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    // Add samples array as a property
    private let samples: [Sample] = TypeBeat.samples
    
    @Published var activeSamples: Set<Int> = []
    @Published var bpm: Double = 84.0 {
        didSet {
            updateMasterClock(newBPM: bpm)
        }
    }
    
    @Published var pitchLock: Bool = false {
        didSet {
            adjustPlaybackRatesAndKeepPhase()
        }
    }

    @Published var isPlaying: Bool = false
    @Published var isEngineReady: Bool = false
    
    // Master Clock Properties
    @Published private var masterClock: AVAudioTime?
    private var masterLoopFrames: AVAudioFramePosition = 0
    private let beatsPerBar = 4.0
    private let totalBars = 16.0
    private var masterLoopDuration: TimeInterval {
        let totalBeats = beatsPerBar * totalBars  // 4 beats/bar * 16 bars = 64 beats
        let secondsPerBeat = 60.0 / bpm
        return totalBeats * secondsPerBeat
    }
    private var sampleRate: Double {
        engine.outputNode.outputFormat(forBus: 0).sampleRate
    }
    
    private let engine = AVAudioEngine()
    private var players: [Int: AVAudioPlayerNode] = [:]
    private var mixers: [Int: AVAudioMixerNode] = [:]
    private var varispeedNodes: [Int: AVAudioUnitVarispeed] = [:]
    private var timePitchNodes: [Int: AVAudioUnitTimePitch] = [:]
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var phaseCorrection: [Int: TimeInterval] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var referenceStartTime: AVAudioTime?
    
    // Add these new properties
    private let phaseLockQueue = DispatchQueue(label: "com.typebeat.phaselock")
    private var masterFramePosition: AVAudioFramePosition = 0
    private var lastKnownPosition: [Int: AVAudioFramePosition] = [:]
    private let maxPhaseDrift: Double = 0.0005 // 0.5ms maximum drift

    // Update the timer property to use Any
    private var progressUpdateTimer: Any?
    
    // Add a subject for BPM updates
    private let bpmSubject = PassthroughSubject<Double, Never>()
    
    private init() {
        setupAudioSession()
        setupEngine()
        
        // Initialize master clock with a small delay for setup
        masterClock = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        masterLoopFrames = AVAudioFramePosition(masterLoopDuration * sampleRate)

        // Modify BPM subscription to maintain continuous playback
        bpmSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newBPM in
                guard let self = self else { return }
                self.bpm = newBPM
                
                // Only proceed with sync if we're playing
                if self.isPlaying {
                    // Calculate next beat time for smooth transition
                    self.resetReferenceStartTimeToNearestBeat()
                    
                    // Adjust rates while maintaining playback
                    for (sampleId, _) in self.players {
                        if let sample = self.samples.first(where: { $0.id == sampleId }) {
                            self.adjustPlaybackRates(for: sample)
                        }
                    }
                    
                    // Update phase without stopping
                    self.adjustPlaybackRatesAndKeepPhase()
                } else {
                    // If not playing, just update the rates
                    for (sampleId, _) in self.players {
                        if let sample = self.samples.first(where: { $0.id == sampleId }) {
                            self.adjustPlaybackRates(for: sample)
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupAudioSession() {
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
        }
    }
    
    private func setupEngine() {
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        
        do {
            try engine.start()
            isEngineReady = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func updateMasterClock(newBPM: Double) {
        guard let currentMasterClock = masterClock else {
            masterClock = AVAudioTime(hostTime: mach_absolute_time())
            return
        }
        
        // Calculate current phase position
        let currentTime = AVAudioTime(hostTime: mach_absolute_time())
        let elapsedTime = currentTime.timeIntervalSince(currentMasterClock)
        let currentPhase = elapsedTime.truncatingRemainder(dividingBy: masterLoopDuration)
        
        // Update master clock to maintain phase
        masterClock = currentTime.offset(seconds: -currentPhase)
        masterLoopFrames = AVAudioFramePosition(masterLoopDuration * sampleRate)
        
        if isPlaying {
            // Calculate next beat boundary for smooth transition
            let nextBeatTime = calculatePreciseStartTime()
            
            // Update each player without stopping
            for (sampleId, player) in players {
                guard let buffer = buffers[sampleId] else { continue }
                
                // Schedule the next loop to start at the beat boundary
                player.scheduleBuffer(buffer, 
                                    at: nextBeatTime, 
                                    options: [.loops, .interruptsAtLoop],
                                    completionCallbackType: .dataPlayedBack) { _ in
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                    }
                }
                
                // Don't stop the current playback - it will transition smoothly
                if let sample = samples.first(where: { $0.id == sampleId }) {
                    adjustPlaybackRates(for: sample)
                }
            }
        }
    }
    
    private func resyncSample(_ sampleId: Int) {
        guard let player = players[sampleId],
              let buffer = buffers[sampleId],
              let clock = masterClock else { return }
        
        player.stop()
        player.scheduleBuffer(buffer, at: clock, options: [.loops, .interruptsAtLoop])
        player.play()
    }
    
    private func nextQuantizedStartTime() -> AVAudioTime {
        guard let masterClock = masterClock else {
            return AVAudioTime(hostTime: mach_absolute_time())
        }
        
        let now = AVAudioTime(hostTime: mach_absolute_time())
        let elapsedTime = now.timeIntervalSince(masterClock)
        let currentLoopPosition = elapsedTime.truncatingRemainder(dividingBy: masterLoopDuration)
        let timeToNextLoop = masterLoopDuration - currentLoopPosition
        
        return now.offset(seconds: timeToNextLoop)
    }
    
    private func monitorPhase(for sampleId: Int) {
        guard let player = players[sampleId],
              let masterClock = masterClock else { return }
        
        let playerTime = player.lastRenderTime ?? AVAudioTime(hostTime: mach_absolute_time())
        let timeSinceMaster = playerTime.timeIntervalSince(masterClock)
        let currentPhase = timeSinceMaster.truncatingRemainder(dividingBy: masterLoopDuration)
        
        // If phase drift exceeds threshold, apply correction
        let threshold = 0.002 // 2ms threshold
        if abs(currentPhase) > threshold {
            phaseCorrection[sampleId] = -currentPhase
            resyncSample(sampleId)
        }
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
    
    func loopProgress() -> Double {
        guard isPlaying, let masterClock = masterClock else { return 0.0 }
        
        let currentTime = AVAudioTime(hostTime: mach_absolute_time())
        let elapsedTime = currentTime.timeIntervalSince(masterClock)
        
        // Calculate progress based on master loop duration
        let progress = elapsedTime.truncatingRemainder(dividingBy: masterLoopDuration) / masterLoopDuration
        return max(0.0, min(1.0, progress))
    }
    
    private func calculatePreciseStartTime() -> AVAudioTime {
        let outputLatency = engine.outputNode.presentationLatency
        let currentTime = engine.outputNode.lastRenderTime ?? AVAudioTime(hostTime: mach_absolute_time())
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let currentSample = currentTime.sampleTime
        let samplesPerBeat = sampleRate * (60.0 / bpm)
        
        // Calculate next beat boundary with higher precision
        let currentBeatPosition = Double(currentSample) / samplesPerBeat
        let nextBeatNumber = ceil(currentBeatPosition)
        let nextBeatSample = nextBeatNumber * samplesPerBeat
        
        // Calculate precise time until next beat
        let timeUntilNextBeat = Double(Int64(nextBeatSample) - currentSample) / sampleRate
        
        // Account for both output latency and minimum scheduling buffer
        let minimumSchedulingBuffer = 0.008 // 8ms minimum scheduling buffer
        let totalOffset = timeUntilNextBeat + minimumSchedulingBuffer - outputLatency
        
        // Convert to host time with nanosecond precision
        let hostTimePerSecond = Double(NSEC_PER_SEC)
        let futureHostTime = currentTime.hostTime + UInt64(hostTimePerSecond * totalOffset)
        
        return AVAudioTime(hostTime: futureHostTime)
    }
    
    private func scheduleAndPlay(_ player: AVAudioPlayerNode, 
                               buffer: AVAudioPCMBuffer, 
                               sampleId: Int) {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let framesPerLoop = AVAudioFramePosition(masterLoopDuration * sampleRate)
        
        // Ensure mixer starts at 0 volume
        if let mixer = mixers[sampleId] {
            mixer.outputVolume = 0
        }
        
        if !isPlaying {
            let startTime = AVAudioTime(hostTime: mach_absolute_time())
            masterClock = startTime
            masterLoopFrames = framesPerLoop
            
            // Only schedule the buffer, don't play it
            player.scheduleBuffer(buffer, at: startTime, options: .loops)
            return  // Don't start playing or set isPlaying to true
        }
        
        // If we're already playing, schedule and play immediately
        player.scheduleBuffer(buffer, at: masterClock, options: .loops)
        player.play(at: masterClock)
    }
    
    private func startPhaseChecking(for sampleId: Int) {
        guard isPlaying else { return }
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self,
                  self.isPlaying,
                  self.players[sampleId] != nil else {
                timer.invalidate()
                return
            }
            
            self.checkAndCorrectPhase(for: sampleId)
        }
    }
    
    private func checkAndCorrectPhase(for sampleId: Int) {
        guard let player = players[sampleId],
              let firstPlayer = players.first?.value,
              let playerTime = player.lastRenderTime,
              let firstPlayerTime = firstPlayer.lastRenderTime,
              playerTime.isSampleTimeValid,
              firstPlayerTime.isSampleTimeValid else { return }
        
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let framesPerLoop = AVAudioFramePosition(masterLoopDuration * sampleRate)
        
        let playerPosition = playerTime.sampleTime % framesPerLoop
        let masterPosition = firstPlayerTime.sampleTime % framesPerLoop
        
        if abs(playerPosition - masterPosition) > 48 { // 1ms at 48kHz
            let correction = AVAudioTime(
                sampleTime: firstPlayerTime.sampleTime,
                atRate: sampleRate
            )
            
            if let buffer = buffers[sampleId] {
                player.scheduleBuffer(buffer, at: correction, options: [.loops, .interruptsAtLoop]) { [weak self] in
                    self?.checkAndCorrectPhase(for: sampleId)
                }
            }
        }
    }
    
    func addSampleToPlay(_ sample: Sample) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Create nodes
            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()
            let varispeed = AVAudioUnitVarispeed()
            let timePitch = AVAudioUnitTimePitch()

            // Ensure we're on the main thread for UI updates
            DispatchQueue.main.async {
                self.engine.attach(player)
                self.engine.attach(varispeed)
                self.engine.attach(timePitch)
                self.engine.attach(mixer)
            }

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
                
                // Store buffer before connecting nodes
                self.buffers[sample.id] = buffer
                
                // Connect nodes on main thread
                DispatchQueue.main.async {
                    self.engine.connect(player, to: varispeed, format: processingFormat)
                    self.engine.connect(varispeed, to: timePitch, format: processingFormat)
                    self.engine.connect(timePitch, to: mixer, format: processingFormat)
                    self.engine.connect(mixer, to: self.engine.mainMixerNode, format: processingFormat)

                    // Store nodes
                    self.players[sample.id] = player
                    self.mixers[sample.id] = mixer
                    self.varispeedNodes[sample.id] = varispeed
                    self.timePitchNodes[sample.id] = timePitch

                    // Ensure mixer starts at 0 volume
                    mixer.outputVolume = 0.0
                    
                    // Adjust playback rates before scheduling
                    self.adjustPlaybackRates(for: sample)
                    
                    // Schedule with precise timing but don't force play
                    self.scheduleAndPlay(player, buffer: buffer, sampleId: sample.id)
                    
                    // Update UI state
                    self.activeSamples.insert(sample.id)
                }
            } catch {
                print("Error loading audio file: \(error)")
            }
        }
    }

    func setMasterVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }
    
    func togglePlayback() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPlaying.toggle()
            
            if self.isPlaying {
                self.startAllPlayersInSync()
            } else {
                self.stopAllPlayers()
            }
        }
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
        guard let currentMasterClock = masterClock else { return }
        
        let hostTimeNow = mach_absolute_time()
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        
        let elapsedHostTime = Double(hostTimeNow - currentMasterClock.hostTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
        let elapsedTimeInSeconds = elapsedHostTime / Double(NSEC_PER_SEC)
        
        let beatsPerSecond = bpm / 60.0
        let elapsedBeats = elapsedTimeInSeconds * beatsPerSecond
        let nearestBeatBoundary = round(elapsedBeats) / beatsPerSecond
        
        let nearestBeatOffsetSeconds = nearestBeatBoundary - elapsedTimeInSeconds
        let newHostTime = currentMasterClock.hostTime + secondsToHostTime(nearestBeatOffsetSeconds)
        
        // Update the published property
        self.masterClock = AVAudioTime(hostTime: newHostTime)
    }

    private func initializeReferenceStartTimeIfNeeded() {
        if referenceStartTime == nil {
            referenceStartTime = AVAudioTime(hostTime: mach_absolute_time())
        }
    }
    
    func togglePitchLockWithoutRestart() {
        DispatchQueue.main.async {
            self.pitchLock.toggle()
        }
        adjustPlaybackRatesAndKeepPhase()
    }

    private func adjustPlaybackRatesAndKeepPhase() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            for (sampleId, _) in self.players {
                if let sample = self.samples.first(where: { $0.id == sampleId }) {
                    self.adjustPlaybackRates(for: sample)
                }
            }
        }
    }

    private func restartAllPlayersWithAdjustedPhase() {
        let nextBeat = calculatePreciseStartTime()
        masterClock = nextBeat
        
        for (sampleId, player) in players {
            guard let buffer = buffers[sampleId] else { continue }
            
            if let sample = samples.first(where: { $0.id == sampleId }) {
                adjustPlaybackRates(for: sample)
            }
            
            // Schedule the buffer at the next beat boundary
            player.stop()
            player.scheduleBuffer(buffer, at: nextBeat, options: [.loops, .interruptsAtLoop])
            player.play(at: nextBeat)
        }
        
        // Maintain playing state
        isPlaying = true
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
        
        // Update @Published property on main thread
        DispatchQueue.main.async {
            self.activeSamples.remove(sample.id)
        }
    }
    
    func setVolume(for sample: Sample, volume: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let mixer = self.mixers[sample.id] else { return }
            mixer.outputVolume = volume
        }
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

    public func stopAllPlayers() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPlaying = false
            
            // Stop the progress updates
            if let timer = self.progressUpdateTimer as? Timer {
                timer.invalidate()
            } else if let displayLink = self.progressUpdateTimer as? CADisplayLink {
                displayLink.invalidate()
            }
            self.progressUpdateTimer = nil
            
            // Stop all players on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                for player in self.players.values {
                    player.stop()
                }
                DispatchQueue.main.async {
                    self.masterClock = nil
                }
            }
        }
    }
    
    private func secondsToHostTime(_ seconds: Double) -> UInt64 {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        
        // Ensure positive values
        let safeSeconds = max(0, seconds)
        let nanoSeconds = safeSeconds * Double(NSEC_PER_SEC)
        
        // Safe conversion avoiding negative numbers
        let denomOverNumer = Double(timebaseInfo.denom) / Double(timebaseInfo.numer)
        let hostTicks = nanoSeconds * denomOverNumer
        
        // Ensure we don't get negative values
        return hostTicks > 0 ? UInt64(hostTicks) : 0
    }

    func stopAllPlayback() {
        // Stop all currently playing samples
        for sample in activeSamples {
            if let player = players[sample] {
                player.stop()
            }
        }
        
        DispatchQueue.main.async {
            self.activeSamples.removeAll()
            self.isPlaying = false
        }
        
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
        bpmSubject.send(newBPM)
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

    private func startAllPlayersInSync() {
        // Calculate start time slightly in the future
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.05))
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.masterClock = startTime
        }
        
        // Start players on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for (sampleId, player) in self.players {
                guard let buffer = self.buffers[sampleId] else { continue }
                player.stop() // Ensure clean state
                
                player.scheduleBuffer(buffer, 
                                   at: startTime, 
                                   options: [.loops, .interruptsAtLoop],
                                   completionCallbackType: .dataPlayedBack) { _ in
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                    }
                }
                player.play(at: startTime)
            }
            
            // Start progress updates on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.startProgressUpdates()
            }
        }
    }

    func loopProgress(for sampleId: Int) -> Double {
        guard isPlaying, let masterClock = masterClock else { return 0.0 }
        
        let currentTime = AVAudioTime(hostTime: mach_absolute_time())
        let elapsedTime = currentTime.timeIntervalSince(masterClock)
        
        // Calculate progress based on master loop duration
        let progress = elapsedTime.truncatingRemainder(dividingBy: masterLoopDuration) / masterLoopDuration
        return max(0.0, min(1.0, progress))
    }

    private func startProgressUpdates() {
        // Stop any existing timer
        if let timer = progressUpdateTimer as? Timer {
            timer.invalidate()
        } else if let displayLink = progressUpdateTimer as? CADisplayLink {
            displayLink.invalidate()
        }
        progressUpdateTimer = nil
        
        // Create new DisplayLink
        let displayLink = CADisplayLink(target: self, selector: #selector(updateProgress))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink.add(to: .main, forMode: .common)
        
        progressUpdateTimer = displayLink
    }

    @objc private func updateProgress() {
        // Force UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    // Add this public method
    func play() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPlaying = true
            self.startAllPlayersInSync()
        }
    }

}

// Helper extension for AVAudioTime calculations
extension AVAudioTime {
    func timeIntervalSince(_ other: AVAudioTime) -> TimeInterval {
        // Handle the UInt64 subtraction safely
        let currentTime = Int64(bitPattern: self.hostTime)
        let otherTime = Int64(bitPattern: other.hostTime)
        
        // Calculate difference using Int64 to handle negative values
        let hostTimeDiff = currentTime - otherTime
        
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        
        // Convert to TimeInterval (Double) after all integer math is done
        let numer = Double(timebase.numer)
        let denom = Double(timebase.denom)
        let nsec = Double(NSEC_PER_SEC)
        
        return Double(hostTimeDiff) * numer / (denom * nsec)
    }
    
    // Helper method for safer time offset calculations
    func offset(seconds: TimeInterval) -> AVAudioTime {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        
        let nsecs = seconds * Double(NSEC_PER_SEC)
        let hostTicks = (nsecs * Double(timebase.denom)) / Double(timebase.numer)
        
        // Safe conversion to UInt64
        let offsetTicks = Int64(hostTicks)
        let newHostTime = Int64(bitPattern: self.hostTime) + offsetTicks
        
        // Ensure we don't go negative
        return AVAudioTime(hostTime: UInt64(max(0, newHostTime)))
    }
}
