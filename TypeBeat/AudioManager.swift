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

    private let engine = AVAudioEngine()
    private var players: [Int: AVAudioPlayerNode] = [:]
    private var mixers: [Int: AVAudioMixerNode] = [:]
    private var varispeedNodes: [Int: AVAudioUnitVarispeed] = [:]
    private var timePitchNodes: [Int: AVAudioUnitTimePitch] = [:]
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var referenceStartTime: AVAudioTime?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupAudioSession()
        setupEngineNodes()
        
        do {
            // Initial start/stop cycle to initialize the engine
            try engine.start()
            engine.pause()  // Use pause instead of stop for smoother initialization
            
            // Now start the engine again but keep playback stopped
            try engine.start()
            initializeReferenceStartTimeIfNeeded()
        } catch {
            print("Error starting audio engine: \(error)")
        }
        isPlaying = false
        stopAllPlayers()
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
        initializeReferenceStartTimeIfNeeded()
        guard let startTime = referenceStartTime else {
            print("Reference start time not initialized! Using fallback time.")
            let fallbackHostTime = mach_absolute_time()
            return AVAudioTime(hostTime: fallbackHostTime)
        }
        
        // Calculate the next beat boundary
        let currentTime = AVAudioTime(hostTime: mach_absolute_time())
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let samplesPerBeat = (60.0 / bpm) * sampleRate
        let currentSample = currentTime.sampleTime
        let nextBeatSample = ceil(Double(currentSample) / samplesPerBeat) * samplesPerBeat
        
        return AVAudioTime(sampleTime: Int64(nextBeatSample), atRate: sampleRate)
    }
    
    func addSampleToPlay(_ sample: Sample) {
        // If we're playing, use the existing reference time
        if isPlaying && referenceStartTime == nil {
            referenceStartTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        }
        
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()
        let varispeed = AVAudioUnitVarispeed()
        let timePitch = AVAudioUnitTimePitch()

        engine.attach(player)
        engine.attach(varispeed)
        engine.attach(timePitch)
        engine.attach(mixer)
        
        let filenameWithId = String(format: "%08d", sample.id) + "-body"

        guard let url = Bundle.main.url(forResource: filenameWithId, withExtension: "mp3") else {
            print("Could not find file \(sample.fileName)")
            return
        }

        do {
            let file = try AVAudioFile(forReading: url)
            let processingFormat = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            
            // Calculate expected frame count based on BPM and bars
            let sampleRate = processingFormat.sampleRate
            let expectedBeats = 16.0 * 4.0  // 16 bars * 4 beats per bar
            let secondsPerBeat = 60.0 / sample.bpm
            let expectedDuration = expectedBeats * secondsPerBeat
            let expectedFrameCount = AVAudioFrameCount(expectedDuration * sampleRate)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: expectedFrameCount) else { return }
            
            try file.read(into: buffer, frameCount: min(frameCount, expectedFrameCount))
            buffer.frameLength = expectedFrameCount
            
            buffers[sample.id] = buffer
            
            engine.connect(player, to: varispeed, format: processingFormat)
            engine.connect(varispeed, to: timePitch, format: processingFormat)
            engine.connect(timePitch, to: mixer, format: processingFormat)
            engine.connect(mixer, to: engine.mainMixerNode, format: processingFormat)

            players[sample.id] = player
            mixers[sample.id] = mixer
            varispeedNodes[sample.id] = varispeed
            timePitchNodes[sample.id] = timePitch

            adjustPlaybackRates(for: sample)
            mixer.outputVolume = 0.0

            if let startTime = referenceStartTime {
                player.scheduleBuffer(buffer, at: startTime, options: [.loops, .interruptsAtLoop])
                if isPlaying {
                    player.play(at: startTime)
                }
            }

            activeSamples.insert(sample.id)
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
            do {
                try engine.start()
                // Reset reference time when starting playback
                referenceStartTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
                // Restart ALL players with the new reference time
                for (sampleId, player) in players {
                    if let buffer = buffers[sampleId] {
                        player.stop()
                        player.scheduleBuffer(buffer, at: referenceStartTime, options: [.loops, .interruptsAtLoop])
                        player.play(at: referenceStartTime)
                    }
                }
            } catch {
                isPlaying = false
                print("Failed to start engine: \(error)")
            }
        } else {
            stopAllPlayers()
            engine.stop()
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

    func restartAllPlayersWithAdjustedPhase() {
        guard !players.isEmpty else { return }
        
        // Stop all players
        for player in players.values {
            player.stop()
        }
        
        // Reset reference time
        referenceStartTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        
        // Restart all players with the same reference time
        for (sampleId, player) in players {
            guard let buffer = buffers[sampleId] else { continue }
            
            if let sample = samples.first(where: { $0.id == sampleId }) {
                adjustPlaybackRates(for: sample)
            }
            
            if let startTime = referenceStartTime {
                player.scheduleBuffer(buffer, at: startTime, options: .loops)
                player.play()
            }
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
        } else {
            varispeed.rate = Float(rate)
            timePitch.rate = 1.0
            timePitch.pitch = 0.0
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

}
