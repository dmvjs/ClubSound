import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class AudioManager {
    static let shared = AudioManager()

    private let samples: [Sample] = TypeBeat.samples

    var activeSamples: Set<Int> = []
    var bpm: Double = 84.0 {
        didSet { updateMasterClock() }
    }

    var pitchLock: Bool = false {
        didSet { adjustAllPlaybackRates() }
    }

    var isPlaying: Bool = false
    var isEngineReady: Bool = false

    // Master Clock
    private var masterClock: AVAudioTime?
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
    private var players: [Int: AVAudioPlayerNode] = [:]
    private var mixers: [Int: AVAudioMixerNode] = [:]
    private var varispeedNodes: [Int: AVAudioUnitVarispeed] = [:]
    private var timePitchNodes: [Int: AVAudioUnitTimePitch] = [:]
    private var buffers: [Int: AVAudioPCMBuffer] = [:]

    private var masterStartTime: AVAudioTime?

    private var masterLoopLength: AVAudioFramePosition {
        AVAudioFramePosition(masterLoopDuration * sampleRate)
    }

    private init() {
        setupAudioSession()
        setupEngine()

        masterClock = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        masterLoopFrames = AVAudioFramePosition(masterLoopDuration * sampleRate)

        engine.prepare()
        try? engine.start()
    }

    /// Stops playback and removes every active sample. Used when the root
    /// view tree is about to be torn down (e.g. on language change) so the
    /// engine state and the view state stay consistent.
    func reset() {
        stopAllPlayers()
        for sample in samples where activeSamples.contains(sample.id) {
            removeSampleFromPlay(sample)
        }
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

    private func updateMasterClock() {
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
                                      completionHandler: nil)
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

        if rawProgress > 0.99 { return 1.0 }
        if rawProgress < 0.01 { return 0.0 }
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
        // File I/O happens off-main so we don't block the audio/UI thread.
        guard let buffer = await Self.loadBuffer(for: sample) else { return }

        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()
        let varispeed = AVAudioUnitVarispeed()
        let timePitch = AVAudioUnitTimePitch()

        engine.attach(player)
        engine.attach(mixer)
        engine.attach(varispeed)
        engine.attach(timePitch)

        engine.connect(player, to: varispeed, format: buffer.format)
        engine.connect(varispeed, to: timePitch, format: buffer.format)
        engine.connect(timePitch, to: mixer, format: buffer.format)
        engine.connect(mixer, to: engine.mainMixerNode, format: buffer.format)

        // Silence the mixer AFTER it's wired into the engine — setting
        // outputVolume before attach gets overwritten when the node joins the
        // render graph, which would leak a frame of full-volume audio before
        // the view's setVolume call lands.
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

        activeSamples.insert(sample.id)
    }

    /// Loads an audio file off the main actor so the I/O doesn't stall UI or
    /// audio rendering. Returns nil if the file can't be located or decoded.
    nonisolated private static func loadBuffer(for sample: Sample) async -> AVAudioPCMBuffer? {
        await Task.detached {
            var url: URL?
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                let testBundle = Bundle(for: AudioManager.self)
                url = testBundle.url(forResource: sample.fileName, withExtension: nil)
            }
            #endif
            url = url ?? Bundle.main.url(forResource: sample.fileName, withExtension: "mp3")

            guard let fileURL = url,
                  let file = try? AVAudioFile(forReading: fileURL),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else {
                print("Could not load audio file: \(sample.fileName)")
                return nil
            }
            do {
                try file.read(into: buffer)
                return buffer
            } catch {
                print("Failed to read \(sample.fileName): \(error)")
                return nil
            }
        }.value
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
        } else if let slice = Self.bufferSlice(buffer,
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
    nonisolated private static func bufferSlice(_ source: AVAudioPCMBuffer,
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
        pitchLock.toggle()
    }

    private func adjustAllPlaybackRates() {
        for sampleId in players.keys {
            if let sample = samples.first(where: { $0.id == sampleId }) {
                adjustPlaybackRates(for: sample)
            }
        }
    }

    func removeSampleFromPlay(_ sample: Sample) {
        guard let player = players[sample.id] else { return }

        activeSamples.remove(sample.id)
        player.stop()

        if let mixer = mixers.removeValue(forKey: sample.id) {
            engine.detach(mixer)
        }
        if let varispeed = varispeedNodes.removeValue(forKey: sample.id) {
            engine.detach(varispeed)
        }
        if let timePitch = timePitchNodes.removeValue(forKey: sample.id) {
            engine.detach(timePitch)
        }
        engine.detach(player)

        players.removeValue(forKey: sample.id)
        buffers.removeValue(forKey: sample.id)

        if players.isEmpty {
            masterStartTime = nil
            isPlaying = false
        }
    }

    func setVolume(for sample: Sample, volume: Float) {
        mixers[sample.id]?.outputVolume = volume
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

    func stopAllPlayers() {
        isPlaying = false
        masterStartTime = nil
        for player in players.values {
            player.stop()
            player.reset()
        }
    }

    func play() {
        isPlaying = true
        startAllPlayersInSync()
    }

    private func secondsToHostTime(_ seconds: Double) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanos = seconds * Double(NSEC_PER_SEC)
        return UInt64(nanos * Double(timebase.denom) / Double(timebase.numer))
    }

    func updateBPM(to newBPM: Double) {
        bpm = newBPM
        if isPlaying {
            startAllPlayersInSync()
        }
    }

}

// MARK: - Test hooks
//
// Test-only accessors. Gated to DEBUG so the production binary doesn't
// ship them and so internal state stays private to production callers.
// The test bundle is built in Debug, so these are available to XCTest.

#if DEBUG
extension AudioManager {
    func testPlayer(for sampleId: Int) -> AVAudioPlayerNode? {
        players[sampleId]
    }

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
#endif

// MARK: - AVAudioTime helpers

extension AVAudioTime {
    func timeIntervalSince(_ other: AVAudioTime) -> TimeInterval {
        let currentTime = Int64(bitPattern: hostTime)
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
        let newHostTime = Int64(bitPattern: hostTime) + offsetTicks
        return AVAudioTime(hostTime: UInt64(max(0, newHostTime)))
    }
}
