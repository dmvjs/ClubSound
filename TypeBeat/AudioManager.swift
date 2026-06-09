import Foundation
import AVFoundation
import SwiftUI

// @unchecked Sendable is a placeholder until the @MainActor / actor migration:
// closures captured by AVAudioPlayerNode callbacks are inferred @Sendable, and
// the real fix is to confine all mutable state to a single isolation domain.
final class AudioManager: ObservableObject, @unchecked Sendable {
    static let shared = AudioManager()

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

    // Master Clock
    @Published private var masterClock: AVAudioTime?
    private var masterLoopFrames: AVAudioFramePosition = 0
    private let beatsPerBar = 4.0
    private let totalBars = 16.0
    private var masterLoopDuration: TimeInterval {
        let totalBeats = beatsPerBar * totalBars  // 64 beats
        let secondsPerBeat = 60.0 / bpm
        return totalBeats * secondsPerBeat
    }
    private var sampleRate: Double {
        engine.outputNode.outputFormat(forBus: 0).sampleRate
    }

    private let engine = AVAudioEngine()
    internal var players: [Int: AVAudioPlayerNode] = [:]
    private var mixers: [Int: AVAudioMixerNode] = [:]
    private var varispeedNodes: [Int: AVAudioUnitVarispeed] = [:]
    private var timePitchNodes: [Int: AVAudioUnitTimePitch] = [:]
    private var buffers: [Int: AVAudioPCMBuffer] = [:]

    internal var masterStartTime: AVAudioTime?
    private var syncTimer: DispatchSourceTimer?

    internal var masterLoopLength: AVAudioFramePosition {
        AVAudioFramePosition(masterLoopDuration * sampleRate)
    }

    private init() {
        setupAudioSession()
        setupEngine()

        masterClock = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        masterLoopFrames = AVAudioFramePosition(masterLoopDuration * sampleRate)

        engine.prepare()
        try? engine.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: NSNotification.Name("LanguageChanged"),
            object: nil
        )
    }

    @objc private func handleLanguageChange() {
        stopAllPlayers()
        activeSamples.removeAll()

        players.removeAll()
        mixers.removeAll()
        varispeedNodes.removeAll()
        timePitchNodes.removeAll()
        buffers.removeAll()

        engine.stop()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.setupEngine()
            self.engine.prepare()
            try? self.engine.start()
            self.isPlaying = false
        }

        objectWillChange.send()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredIOBufferDuration(0.005)
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("❌ Failed to set up audio session: \(error.localizedDescription)")
            #if DEBUG
            assertionFailure("Audio session setup failed!")
            #endif
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

        let currentTime = AVAudioTime(hostTime: mach_absolute_time())
        let elapsedTime = currentTime.timeIntervalSince(currentMasterClock)
        let currentPhase = elapsedTime.truncatingRemainder(dividingBy: masterLoopDuration)

        masterClock = currentTime.offset(seconds: -currentPhase)
        masterLoopFrames = AVAudioFramePosition(masterLoopDuration * sampleRate)

        if isPlaying {
            let nextBeatTime = calculatePreciseStartTime()

            for (sampleId, player) in players {
                guard let buffer = buffers[sampleId] else { continue }

                player.scheduleBuffer(buffer,
                                    at: nextBeatTime,
                                    options: [.loops, .interruptsAtLoop],
                                    completionCallbackType: .dataPlayedBack) { _ in
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                    }
                }

                if let sample = samples.first(where: { $0.id == sampleId }) {
                    adjustPlaybackRates(for: sample)
                }
            }
        }
    }

    func loopProgress() -> Double {
        guard isPlaying,
              masterClock != nil,
              let startTime = masterStartTime else { return 0.0 }

        let currentTime = AVAudioTime(hostTime: mach_absolute_time())
        let elapsedTime = currentTime.timeIntervalSince(startTime)

        let rawProgress = elapsedTime.truncatingRemainder(dividingBy: masterLoopDuration) / masterLoopDuration

        if rawProgress > 0.99 {
            return 1.0
        } else if rawProgress < 0.01 {
            return 0.0
        }

        return rawProgress
    }

    private func calculatePreciseStartTime() -> AVAudioTime {
        guard let currentTime = engine.outputNode.lastRenderTime,
              currentTime.isSampleTimeValid else {
            return AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        }

        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let currentPosition = currentTime.sampleTime
        let samplesPerBeat = AVAudioFramePosition(sampleRate * 60.0 / bpm)

        let nextBeatPosition = currentPosition + (samplesPerBeat - (currentPosition % samplesPerBeat))

        return AVAudioTime(sampleTime: nextBeatPosition, atRate: sampleRate)
    }

    func addSampleToPlay(_ sample: Sample) async {
        do {
            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()
            let varispeed = AVAudioUnitVarispeed()
            let timePitch = AVAudioUnitTimePitch()

            var url: URL?
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                let testBundle = Bundle(for: type(of: self))
                url = testBundle.url(forResource: sample.fileName, withExtension: nil)
            }
            #endif

            if url == nil {
                url = Bundle.main.url(forResource: sample.fileName, withExtension: "mp3")
            }

            guard let fileURL = url,
                  let file = try? AVAudioFile(forReading: fileURL),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else {
                print("Could not load audio file: \(sample.fileName)")
                return
            }

            try file.read(into: buffer)

            engine.attach(player)
            engine.attach(mixer)
            engine.attach(varispeed)
            engine.attach(timePitch)

            engine.connect(player, to: varispeed, format: buffer.format)
            engine.connect(varispeed, to: timePitch, format: buffer.format)
            engine.connect(timePitch, to: mixer, format: buffer.format)
            engine.connect(mixer, to: engine.mainMixerNode, format: buffer.format)

            // Silence the mixer AFTER it's wired into the engine — setting
            // outputVolume before attach gets overwritten when the node joins
            // the render graph, which leaks a frame of full-volume audio
            // before ContentView's setVolume call lands.
            mixer.outputVolume = 0.0

            players[sample.id] = player
            mixers[sample.id] = mixer
            varispeedNodes[sample.id] = varispeed
            timePitchNodes[sample.id] = timePitch
            buffers[sample.id] = buffer

            adjustPlaybackRates(for: sample)

            if isPlaying {
                schedulePhaseAligned(player: player, buffer: buffer, rate: bpm / sample.bpm)
            }

            await MainActor.run {
                _ = activeSamples.insert(sample.id)
            }

        } catch {
            print("Error adding sample: \(error)")
        }
    }

    /// Drops a newly-added player into the running graph phase-aligned with the
    /// master loop. Computes the buffer-frame that matches the current master
    /// phase, plays the remainder of the current loop as a sliced buffer, then
    /// hands off to a looping scheduleBuffer. Existing players are not touched —
    /// AVAudioEngine maintains their sample-accurate timing on its own.
    ///
    /// `rate` is the effective playback rate (master BPM / sample BPM), the
    /// same value applied to varispeed / timePitch.
    private func schedulePhaseAligned(player: AVAudioPlayerNode,
                                      buffer: AVAudioPCMBuffer,
                                      rate: Double) {
        let leadTime: TimeInterval = 0.02
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(leadTime))

        let bufferFrames = AVAudioFramePosition(buffer.frameLength)
        var frameOffset: AVAudioFramePosition = 0

        if let masterStartTime = masterStartTime {
            let elapsed = startTime.timeIntervalSince(masterStartTime)
            if elapsed > 0 {
                // Effective loop duration in real seconds, accounting for varispeed
                let bufferSampleRate = buffer.format.sampleRate
                let effectiveLoopDuration = Double(buffer.frameLength) / (bufferSampleRate * rate)
                let phaseInLoop = elapsed.truncatingRemainder(dividingBy: effectiveLoopDuration)
                frameOffset = AVAudioFramePosition(phaseInLoop * rate * bufferSampleRate)
                if frameOffset < 0 || frameOffset >= bufferFrames {
                    frameOffset = 0
                }
            }
        }

        if frameOffset == 0 {
            player.scheduleBuffer(buffer, at: startTime, options: [.loops], completionHandler: nil)
        } else if let slice = bufferSlice(buffer,
                                          startingFrame: frameOffset,
                                          frameCount: AVAudioFrameCount(bufferFrames - frameOffset)) {
            // Play the in-phase remainder of the current loop, then loop normally.
            player.scheduleBuffer(slice, at: startTime, completionHandler: nil)
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        } else {
            // Slice failed (unsupported format) — fall back to clean loop start.
            player.scheduleBuffer(buffer, at: startTime, options: [.loops], completionHandler: nil)
        }
        player.play()
    }

    /// Returns a buffer containing the requested frame range of `source`.
    /// Supports float32 non-interleaved buffers (the common-format output of
    /// `AVAudioFile.processingFormat`). Returns nil for other formats.
    private func bufferSlice(_ source: AVAudioPCMBuffer,
                             startingFrame: AVAudioFramePosition,
                             frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard startingFrame >= 0,
              AVAudioFramePosition(frameCount) > 0,
              startingFrame + AVAudioFramePosition(frameCount) <= AVAudioFramePosition(source.frameLength),
              let src = source.floatChannelData,
              let slice = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: frameCount),
              let dst = slice.floatChannelData else {
            return nil
        }

        let channelCount = Int(source.format.channelCount)
        let bytes = Int(frameCount) * MemoryLayout<Float>.size
        for ch in 0..<channelCount {
            memcpy(dst[ch], src[ch].advanced(by: Int(startingFrame)), bytes)
        }
        slice.frameLength = frameCount
        return slice
    }

    func setMasterVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
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

    func removeSampleFromPlay(_ sample: Sample) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let player = self.players[sample.id] else { return }

            self.activeSamples.remove(sample.id)

            player.stop()

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

            self.players.removeValue(forKey: sample.id)
            self.buffers.removeValue(forKey: sample.id)

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
            timePitch.overlap = 8.0
        } else {
            varispeed.rate = Float(rate)
            timePitch.rate = 1.0
            timePitch.pitch = 0.0
            timePitch.overlap = 3.0
        }
    }

    private func startAllPlayersInSync() {
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        masterStartTime = startTime

        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let framesPerLoop = AVAudioFramePosition(masterLoopDuration * sampleRate)
        masterLoopFrames = framesPerLoop

        for player in players.values {
            player.stop()
            player.reset()
        }

        for (sampleId, player) in players {
            guard let buffer = buffers[sampleId] else { continue }
            player.scheduleBuffer(buffer, at: startTime, options: [.loops], completionHandler: nil)
        }

        for player in players.values {
            player.play()
        }
    }

    public func stopAllPlayers() {
        Task { @MainActor in
            isPlaying = false

            stopSyncMonitoring()

            await Task.detached(priority: .userInitiated) {
                for player in self.players.values {
                    player.stop()
                    player.reset()
                }
            }.value

            masterStartTime = nil
        }
    }

    private func stopSyncMonitoring() {
        syncTimer?.cancel()
        syncTimer = nil
        masterStartTime = nil
    }

    public func play() {
        Task { @MainActor in
            isPlaying = true
            startAllPlayersInSync()
        }
    }

    private func secondsToHostTime(_ seconds: Double) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)

        let nanos = seconds * Double(NSEC_PER_SEC)
        return UInt64(nanos * Double(timebase.denom) / Double(timebase.numer))
    }

    func updateBPM(to newBPM: Double) {
        DispatchQueue.main.async {
            self.bpm = newBPM

            if self.isPlaying {
                self.startAllPlayersInSync()
            }
        }
    }

    // MARK: - Test hooks

    func getPlaybackRate(for sample: Sample) -> Float {
        Float(bpm / sample.bpm)
    }

    func getSamplePhase(for sampleId: Int) -> Double {
        guard let player = players[sampleId],
              let playerTime = player.lastRenderTime,
              let startTime = masterStartTime,
              playerTime.isSampleTimeValid else { return 0 }

        let elapsedTime = playerTime.timeIntervalSince(startTime)

        let beatsPerSecond = bpm / 60.0
        let totalPhase = elapsedTime * beatsPerSecond

        return totalPhase.truncatingRemainder(dividingBy: 1.0)
    }

    func getSampleRate(for sampleId: Int) -> Float {
        varispeedNodes[sampleId]?.rate ?? 0
    }
}

// MARK: - AVAudioTime helpers

extension AVAudioTime {
    func timeIntervalSince(_ other: AVAudioTime) -> TimeInterval {
        let currentTime = Int64(bitPattern: self.hostTime)
        let otherTime = Int64(bitPattern: other.hostTime)

        let hostTimeDiff = currentTime - otherTime

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)

        let numer = Double(timebase.numer)
        let denom = Double(timebase.denom)
        let nsec = Double(NSEC_PER_SEC)

        return Double(hostTimeDiff) * numer / (denom * nsec)
    }

    func offset(seconds: TimeInterval) -> AVAudioTime {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)

        let nsecs = seconds * Double(NSEC_PER_SEC)
        let hostTicks = (nsecs * Double(timebase.denom)) / Double(timebase.numer)

        let offsetTicks = Int64(hostTicks)
        let newHostTime = Int64(bitPattern: self.hostTime) + offsetTicks

        return AVAudioTime(hostTime: UInt64(max(0, newHostTime)))
    }
}
