import Foundation
import AVFoundation
import Combine

class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    private let engine = AVAudioEngine()
    private var players: [Int: AVAudioPlayerNode] = [:]
    private var mixers: [Int: AVAudioMixerNode] = [:]
    private var varispeedNodes: [Int: AVAudioUnitVarispeed] = [:]
    private var timePitchNodes: [Int: AVAudioUnitTimePitch] = [:]
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var referenceStartTime: AVAudioTime?
    private var cancellables = Set<AnyCancellable>()

    @Published var bpm: Double = 84.0 {
        didSet {
            restartAllPlayersWithAdjustedPhase()
        }
    }
    
    @Published var pitchLock: Bool = false {
        didSet {
            restartAllPlayersWithAdjustedPhase()
        }
    }

    @Published var isPlaying: Bool = true

    private init() {
        setupAudioSession()
        setupEngineNodes()
        startEngine()
    }
    
    func loopProgress(for sampleId: Int) -> Double {
        guard let startTime = referenceStartTime,
              let buffer = buffers[sampleId],
              let renderTime = engine.outputNode.lastRenderTime else { return 0.0 }

        // Ensure renderTime.hostTime is greater than or equal to startTime.hostTime
        guard renderTime.hostTime >= startTime.hostTime else {
            print("Invalid timing: renderTime.hostTime is less than startTime.hostTime.")
            return 0.0
        }

        // Subtract startTime from renderTime safely
        let elapsedHostTime = renderTime.hostTime - startTime.hostTime
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)

        // Convert elapsed time to seconds
        let elapsedSeconds = Double(elapsedHostTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom) / Double(NSEC_PER_SEC)

        // Calculate loop progress
        let loopDuration = Double(buffer.frameLength) / buffer.format.sampleRate
        return (elapsedSeconds.truncatingRemainder(dividingBy: loopDuration)) / loopDuration
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Error setting up audio session: \(error.localizedDescription)")
        }
    }
    
    private func setupEngineNodes() {
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
    }
    
    private func startEngine() {
        do {
            try engine.start()
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
        }
    }
    
    func addSampleToPlay(_ sample: Sample) {
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
            guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else { return }
            try file.read(into: buffer)
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

            // Schedule the player based on the shared reference start time
            let startTime = calculatePreciseStartTime()
            player.scheduleBuffer(buffer, at: startTime, options: .loops, completionHandler: nil)
            if isPlaying {
                player.play()
            }
        } catch {
            print("Error loading audio file: \(error.localizedDescription)")
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

    private func calculatePreciseStartTime() -> AVAudioTime {
        initializeReferenceStartTimeIfNeeded()
        guard let startTime = referenceStartTime else {
            print("Reference start time not initialized! Using fallback time.")
            let fallbackHostTime = mach_absolute_time()
            return AVAudioTime(hostTime: fallbackHostTime)
        }
        return startTime
    }
    
    func restartAllPlayersFromBeginning() {
        guard !players.isEmpty else { return }

        // Stop all players
        stopAllPlayers()

        // Reset reference start time to the current host time
        referenceStartTime = AVAudioTime(hostTime: mach_absolute_time())

        // Schedule all buffers to start from the beginning
        for (sampleId, player) in players {
            guard let buffer = buffers[sampleId] else { continue }

            // Adjust playback rates for the new BPM
            adjustPlaybackRates(for: samples.first { $0.id == sampleId }!)

            // Schedule the buffer to start from the reference start time
            player.scheduleBuffer(buffer, at: referenceStartTime, options: .loops, completionHandler: nil)
        }

        // Start all players simultaneously
        for player in players.values {
            player.play()
        }
    }


    private func initializeReferenceStartTimeIfNeeded() {
        if referenceStartTime == nil {
            referenceStartTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(1.0))
        }
    }
    
    func togglePlayback() {
        if engine.isRunning {
            // Stop the engine
            stopAllPlayers()
            engine.stop()
            isPlaying = false
        } else {
            // Restart the engine
            do {
                try engine.start()
                restartAllPlayersFromBeginning()
                isPlaying = true
            } catch {
                print("Failed to start engine: \(error)")
            }
        }
    }


    func togglePitchLockWithoutRestart() {
        pitchLock.toggle()
        adjustPlaybackRatesAndKeepPhase()
    }

    private func adjustPlaybackRatesAndKeepPhase() {
        for (sampleId, _) in players {
            if let sample = samples.first(where: { $0.id == sampleId }),
               let varispeed = varispeedNodes[sampleId] {
                let rate = bpm / sample.bpm
                if pitchLock {
                    varispeed.rate = 1.0
                } else {
                    varispeed.rate = Float(rate)
                }
            }
        }
    }

    func restartAllPlayersWithAdjustedPhase() {
        guard !players.isEmpty else { return }
        
        // Stop all players
        for player in players.values {
            player.stop()
        }
        
        // Reset reference start time
        resetReferenceStartTimeToNearestBeat()
        
        // Recalculate start time
        let newStartTime = calculatePreciseStartTime()
        
        // Restart all players with the same start time
        for (sampleId, player) in players {
            guard let buffer = buffers[sampleId] else { continue }
            
            // Adjust playback rates based on the new tempo
            adjustPlaybackRates(for: samples.first { $0.id == sampleId }!)
            
            // Schedule buffer for playback at the new synchronized time
            player.scheduleBuffer(buffer, at: newStartTime, options: .loops, completionHandler: nil)
            player.play()
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
            if player.isPlaying {
                player.stop()
            }
        }
    }
    
    private func secondsToHostTime(_ seconds: Double) -> UInt64 {
        guard seconds >= 0 else { return 0 } // Prevent negative values
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanoSeconds = seconds * Double(NSEC_PER_SEC)
        let nanoSecondsToHostTicks = nanoSeconds / Double(timebaseInfo.numer) * Double(timebaseInfo.denom)
        return UInt64(nanoSecondsToHostTicks)
    }

}
