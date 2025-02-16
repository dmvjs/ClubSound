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
    
    // Add these properties
    private let supportedBPMs: Set<Double> = [69.0, 84.0, 102.0]
    private var masterFramePositions: [Double: AVAudioFramePosition] = [:]
    private var masterStartTime: AVAudioTime?
    private let syncMonitor = DispatchQueue(label: "com.typebeat.sync", qos: .userInteractive)
    private var syncTimer: DispatchSourceTimer?
    
    // Add these properties
    private var masterPhasePosition: Double = 0.0
    private let syncThreshold: Double = 0.0005 // 0.5ms threshold
    private var masterLoopLength: AVAudioFramePosition = 0
    
    // Add these properties at the top of AudioManager class
    private var isTransitioning = false
    private let debounceQueue = DispatchQueue(label: "com.typebeat.debounce")
    private let minimumToggleInterval: TimeInterval = 0.2
    
    private init() {
        setupAudioSession()
        setupEngine()
        
        // Initialize master clock with a small delay for setup
        masterClock = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        masterLoopFrames = AVAudioFramePosition(masterLoopDuration * sampleRate)
        
        // Initialize masterFramePositions immediately
        initializeMasterFrames()
        
        // Initialize engine with maximum quality settings
        engine.prepare()
        try? engine.start()
        
        // Setup BPM subscription
        bpmSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newBPM in
                guard let self = self else { return }
                self.bpm = newBPM
                
                // Only proceed with sync if we're playing
                if self.isPlaying {
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
        guard let currentTime = engine.outputNode.lastRenderTime,
              currentTime.isSampleTimeValid else {
            return AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        }
        
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let currentPosition = currentTime.sampleTime
        let samplesPerBeat = AVAudioFramePosition(sampleRate * 60.0 / bpm)
        
        // Find next beat boundary
        let nextBeatPosition = currentPosition + (samplesPerBeat - (currentPosition % samplesPerBeat))
        
        return AVAudioTime(sampleTime: nextBeatPosition, atRate: sampleRate)
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
        
        // Only correct if significantly out of phase (> 5ms)
        let threshold = AVAudioFramePosition(sampleRate * 0.005) // Convert to frames
        if abs(playerPosition - masterPosition) > threshold {
            // Schedule next loop at master position
            if let buffer = buffers[sampleId] {
                let correction = AVAudioTime(
                    sampleTime: firstPlayerTime.sampleTime,
                    atRate: sampleRate
                )
                player.scheduleBuffer(buffer, at: correction, options: [.loops])
            }
        }
    }
    
    func addSampleToPlay(_ sample: Sample) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.players.keys.contains(sample.id) else { return }
            
            do {
                // Stop any existing playback for this sample
                if let existingMixer = self.mixers[sample.id] {
                    existingMixer.outputVolume = 0
                    if let existingPlayer = self.players[sample.id] {
                        existingPlayer.stop()
                    }
                }
                
                // Create and configure nodes
                let player = AVAudioPlayerNode()
                let mixer = AVAudioMixerNode()
                let varispeed = AVAudioUnitVarispeed()
                let timePitch = AVAudioUnitTimePitch()
                
                // Force volume to absolute zero before any connections
                mixer.outputVolume = 0
                
                // Load audio file and create buffer
                guard let url = Bundle.main.url(forResource: sample.fileName, withExtension: "mp3"),
                      let file = try? AVAudioFile(forReading: url),
                      let buffer = try? AVAudioPCMBuffer(pcmFormat: file.processingFormat, 
                                                        frameCapacity: AVAudioFrameCount(file.length)) else {
                    print("Could not load audio file: \(sample.fileName)")
                    return
                }
                
                try file.read(into: buffer)
                
                // Disconnect any existing nodes
                if let existingMixer = self.mixers[sample.id] {
                    self.engine.disconnectNodeOutput(existingMixer)
                }
                
                // Remove existing nodes
                if let existingPlayer = self.players[sample.id] {
                    self.engine.detach(existingPlayer)
                }
                
                // Connect new nodes
                self.engine.attach(player)
                self.engine.attach(mixer)
                self.engine.attach(varispeed)
                self.engine.attach(timePitch)
                
                self.engine.connect(player, to: varispeed, format: buffer.format)
                self.engine.connect(varispeed, to: timePitch, format: buffer.format)
                self.engine.connect(timePitch, to: mixer, format: buffer.format)
                self.engine.connect(mixer, to: self.engine.mainMixerNode, format: buffer.format)
                
                // Store references AFTER all connections are made
                self.players[sample.id] = player
                self.mixers[sample.id] = mixer
                self.varispeedNodes[sample.id] = varispeed
                self.timePitchNodes[sample.id] = timePitch
                self.buffers[sample.id] = buffer
                
                // Final volume check
                mixer.outputVolume = 0
                
                if self.isPlaying {
                    if self.masterStartTime == nil {
                        self.masterStartTime = AVAudioTime(hostTime: mach_absolute_time())
                    }
                    
                    guard let masterStartTime = self.masterStartTime else {
                        print("No master time reference")
                        return
                    }
                    
                    let currentTime = AVAudioTime(hostTime: mach_absolute_time())
                    let elapsedTime = currentTime.timeIntervalSince(masterStartTime)
                    let loopDuration = 60.0 / self.bpm * 4
                    let loopPosition = elapsedTime.truncatingRemainder(dividingBy: loopDuration)
                    
                    let startTime = masterStartTime.offset(seconds: -loopPosition)
                    player.scheduleBuffer(buffer, at: startTime, options: [.loops])
                    player.play()
                } else {
                    player.scheduleBuffer(buffer, at: nil, options: [.loops])
                }
                
                self.activeSamples.insert(sample.id)
                
                // Verify volume one last time
                DispatchQueue.main.async {
                    if let finalMixer = self.mixers[sample.id] {
                        finalMixer.outputVolume = 0
                    }
                }
                
            } catch {
                print("Error setting up audio: \(error)")
            }
        }
    }

    func setMasterVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }
    
    func togglePlayback() {
        // Use async to prevent UI blocking
        Task { @MainActor in
            isPlaying.toggle()
            
            if isPlaying {
                await startAllPlayersInSync()
            } else {
                await stopAllPlayers()
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let player = self.players[sample.id] else { return }
            
            // Keep activeSamples in sync with nowPlaying
            self.activeSamples.remove(sample.id)
            
            // Stop player before detaching
            player.stop()
            
            // Safely detach nodes
            if self.engine != nil {
                if let mixer = self.mixers[sample.id] {
                    self.engine.detach(mixer)
                    self.mixers.removeValue(forKey: sample.id)
                }
                if let varispeed = self.varispeedNodes[sample.id] {
                    self.engine.detach(varispeed)
                    self.varispeedNodes.removeValue(forKey: sample.id)
                }
                if let timePitch = self.timePitchNodes[sample.id] {
                    self.engine.detach(timePitch)
                    self.timePitchNodes.removeValue(forKey: sample.id)
                }
                self.engine.detach(player)
            }
            
            // Clean up remaining references
            self.players.removeValue(forKey: sample.id)
            self.buffers.removeValue(forKey: sample.id)
            
            // Only stop sync monitoring if no players remain
            if self.players.isEmpty {
                self.stopSyncMonitoring()
                self.isPlaying = false
            }
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

    private func startAllPlayersInSync() async {
        // Create immediate start time with a small buffer for setup
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        masterStartTime = startTime
        
        // Calculate exact loop length for current BPM
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let framesPerLoop = AVAudioFramePosition(masterLoopDuration * sampleRate)
        masterLoopFrames = framesPerLoop
        
        // Stop all players first
        for player in players.values {
            player.stop()
            player.reset()
        }
        
        // Schedule all players with precise timing
        for (sampleId, player) in players {
            guard let buffer = buffers[sampleId] else { continue }
            player.scheduleBuffer(buffer, 
                                at: startTime,
                                options: [.loops],
                                completionCallbackType: .dataPlayedBack) { [weak self] _ in
                // Only check phase if still playing
                guard let self = self, self.isPlaying else { return }
                self.checkAndCorrectPhase(for: sampleId)
            }
        }
        
        // Start all players together
        for player in players.values {
            player.play()
        }
    }

    public func stopAllPlayers() {
        Task { @MainActor in
            // Update UI state immediately
            isPlaying = false
            
            // Stop sync monitoring first
            stopSyncMonitoring()
            
            // Stop all players on background thread
            await Task.detached(priority: .userInitiated) {
                // Stop all players
                for player in self.players.values {
                    player.stop()
                    player.reset()
                }
            }.value
            
            // Reset master state
            masterStartTime = nil
            masterPhasePosition = 0.0
        }
    }

    private func startPhaseMonitoring() {
        syncTimer?.cancel()
        syncTimer = nil
        
        syncTimer = DispatchSource.makeTimerSource(queue: syncMonitor)
        syncTimer?.schedule(deadline: .now(), repeating: .milliseconds(10)) // Less frequent checks
        
        weak var weakSelf = self
        
        syncTimer?.setEventHandler { [weak weakSelf] in
            guard let self = weakSelf,
                  self.isPlaying,
                  let startTime = self.masterStartTime,
                  let (firstId, firstPlayer) = self.players.first,
                  let firstTime = firstPlayer.lastRenderTime,
                  firstTime.isSampleTimeValid else { return }
            
            let masterPosition = firstTime.sampleTime % self.masterLoopLength
            
            // Check each player sequentially instead of in parallel
            for (sampleId, player) in self.players where sampleId != firstId {
                guard let playerTime = player.lastRenderTime,
                      playerTime.isSampleTimeValid else { continue }
                
                let playerPosition = playerTime.sampleTime % self.masterLoopLength
                let drift = abs(playerPosition - masterPosition)
                
                if drift > Int64(self.sampleRate * 0.001) {
                    DispatchQueue.main.async {
                        if let buffer = self.buffers[sampleId] {
                            let correction = AVAudioTime(
                                sampleTime: masterPosition,
                                atRate: self.sampleRate
                            )
                            player.scheduleBuffer(buffer, at: correction, options: [.loops])
                        }
                    }
                }
            }
        }
        
        syncTimer?.resume()
    }

    private func checkPlayerSync(_ sampleId: Int) {
        guard let player = players[sampleId],
              let playerTime = player.lastRenderTime,
              let masterTime = masterStartTime else { return }
        
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let playerFrame = playerTime.sampleTime % masterLoopLength
        let expectedFrame = AVAudioFramePosition((playerTime.timeIntervalSince(masterTime) * sampleRate)) % masterLoopLength
        
        let drift = abs(Double(playerFrame - expectedFrame) / sampleRate)
        
        if drift > syncThreshold {
            // Resync this player
            syncMonitor.async {
                if let buffer = self.buffers[sampleId] {
                    let correction = AVAudioTime(
                        sampleTime: expectedFrame,
                        atRate: sampleRate
                    )
                    player.scheduleBuffer(buffer, at: correction, options: [.loops, .interruptsAtLoop])
                }
            }
        }
    }

    private func stopSyncMonitoring() {
        syncTimer?.cancel()
        syncTimer = nil
        masterStartTime = nil
        masterPhasePosition = 0.0
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

    // Make these non-async again but handle async internally
    public func play() {
        // Prevent rapid toggling
        guard !isTransitioning else { return }
        
        Task { @MainActor in
            isPlaying = true
            await startAllPlayersInSync()
        }
    }

    private func secondsToHostTime(_ seconds: Double) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        
        let nanos = seconds * Double(NSEC_PER_SEC)
        return UInt64(nanos * Double(timebase.denom) / Double(timebase.numer))
    }

    private func initializeMasterFrames() {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let beatsPerBar = 4.0
        let totalBars = 16.0
        let totalBeats = beatsPerBar * totalBars
        
        // Pre-calculate frame positions for common BPMs
        for bpm in [69.0, 84.0, 94.0, 102.0] {
            let secondsPerBeat = 60.0 / bpm
            let loopSeconds = totalBeats * secondsPerBeat
            masterFramePositions[bpm] = AVAudioFramePosition(loopSeconds * sampleRate)
        }
    }

    // Add this function to the AudioManager class
    func updateBPM(to newBPM: Double) {
        DispatchQueue.main.async {
            // Calculate current phase before changing BPM
            let currentPhase = self.loopProgress()
            
            self.bpm = newBPM
            
            // Maintain phase after BPM change
            if self.isPlaying {
                Task {
                    await self.startAllPlayersInSync()
                }
            }
        }
    }

    // Add this function
    func setVolumeForSample(_ sampleId: Int, to volume: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let mixer = self.mixers[sampleId] {
                mixer.outputVolume = volume
            }
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

func changeLanguage(to language: String) {
    // Stop all playback first
    AudioManager.shared.stopAllPlayers()
    
    // Set the new language
    UserDefaults.standard.set(language, forKey: "AppLanguage")
    UserDefaults.standard.synchronize()
    
    // Restart app
    exit(0)
}

