import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class AudioManager {
    static let shared = AudioManager()

    var bpm: Double = 84.0 {
        didSet {
            adjustAllPlaybackRates()
            if isPlaying { startAllPlayersInSync() }
        }
    }
    var pitchLock: Bool = false {
        didSet { adjustAllPlaybackRates() }
    }
    var isPlaying: Bool = false

    private let beatsPerBar = 4.0
    private let totalBars = 16.0
    private var masterLoopDuration: TimeInterval {
        beatsPerBar * totalBars * 60.0 / bpm  // 64 beats
    }

    private let engine = AVAudioEngine()
    private var playing: [Int: PlayingSample] = [:]
    private var masterStartTime: AVAudioTime?

    private struct PlayingSample {
        let sample: Sample
        let player: AVAudioPlayerNode
        let mixer: AVAudioMixerNode
        let varispeed: AVAudioUnitVarispeed
        let timePitch: AVAudioUnitTimePitch
        let buffer: AVAudioPCMBuffer
    }

    private init() {
        setupAudioSession()
        setupEngine()
        engine.prepare()
        try? engine.start()
    }

    /// Stops playback and removes every active sample. Used when the root
    /// view tree is about to be torn down (e.g. on language change) so the
    /// engine state and the view state stay consistent.
    func reset() {
        stopAllPlayers()
        for entry in playing.values {
            engine.detach(entry.mixer)
            engine.detach(entry.varispeed)
            engine.detach(entry.timePitch)
            engine.detach(entry.player)
        }
        playing.removeAll()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("❌ Failed to set up audio session: \(error.localizedDescription)")
            #if DEBUG
            assertionFailure("Audio session setup failed!")
            #endif
        }
    }

    private func setupEngine() {
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        try? engine.start()
    }

    func loopProgress() -> Double {
        guard isPlaying, let startTime = masterStartTime else { return 0.0 }
        let elapsed = AVAudioTime(hostTime: mach_absolute_time()).timeIntervalSince(startTime)
        return elapsed.truncatingRemainder(dividingBy: masterLoopDuration) / masterLoopDuration
    }

    func addSampleToPlay(_ sample: Sample) async {
        // File I/O happens off-main so we don't block the audio/UI thread.
        guard let buffer = await Self.loadBuffer(for: sample) else { return }

        let entry = PlayingSample(
            sample: sample,
            player: AVAudioPlayerNode(),
            mixer: AVAudioMixerNode(),
            varispeed: AVAudioUnitVarispeed(),
            timePitch: AVAudioUnitTimePitch(),
            buffer: buffer
        )

        engine.attach(entry.player)
        engine.attach(entry.mixer)
        engine.attach(entry.varispeed)
        engine.attach(entry.timePitch)

        engine.connect(entry.player, to: entry.varispeed, format: buffer.format)
        engine.connect(entry.varispeed, to: entry.timePitch, format: buffer.format)
        engine.connect(entry.timePitch, to: entry.mixer, format: buffer.format)
        engine.connect(entry.mixer, to: engine.mainMixerNode, format: buffer.format)

        // Silence the mixer AFTER it's wired into the engine — setting
        // outputVolume before attach gets overwritten when the node joins the
        // render graph, which would leak a frame of full-volume audio before
        // the view's setVolume call lands.
        entry.mixer.outputVolume = 0.0

        playing[sample.id] = entry
        applyRate(to: entry)

        if isPlaying {
            schedulePhaseAligned(entry: entry)
        }
    }

    /// Loads an audio file off the main actor so the I/O doesn't stall UI or
    /// audio rendering. Returns nil if the file can't be located or decoded.
    nonisolated private static func loadBuffer(for sample: Sample) async -> AVAudioPCMBuffer? {
        await Task.detached {
            var url: URL?
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                url = Bundle(for: AudioManager.self).url(forResource: sample.fileName, withExtension: nil)
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
    private func schedulePhaseAligned(entry: PlayingSample) {
        let leadTime: TimeInterval = 0.02
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(leadTime))
        let rate = bpm / entry.sample.bpm

        let buffer = entry.buffer
        let bufferFrames = AVAudioFramePosition(buffer.frameLength)
        var frameOffset: AVAudioFramePosition = 0

        if let masterStartTime, startTime.timeIntervalSince(masterStartTime) > 0 {
            let elapsed = startTime.timeIntervalSince(masterStartTime)
            let bufferSampleRate = buffer.format.sampleRate
            let effectiveLoopDuration = Double(buffer.frameLength) / (bufferSampleRate * rate)
            let phaseInLoop = elapsed.truncatingRemainder(dividingBy: effectiveLoopDuration)
            frameOffset = AVAudioFramePosition(phaseInLoop * rate * bufferSampleRate)
            if frameOffset < 0 || frameOffset >= bufferFrames {
                frameOffset = 0
            }
        }

        let player = entry.player
        if frameOffset > 0,
           let slice = Self.bufferSlice(buffer,
                                        startingFrame: frameOffset,
                                        frameCount: AVAudioFrameCount(bufferFrames - frameOffset)) {
            // Play the in-phase remainder of the current loop, then loop normally.
            player.scheduleBuffer(slice, at: startTime, completionHandler: nil)
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        } else {
            // Either at a loop boundary, or buffer-slice fell through — start clean.
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
              frameCount > 0,
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

    func setVolume(for sample: Sample, volume: Float) {
        playing[sample.id]?.mixer.outputVolume = volume
    }

    func removeSampleFromPlay(_ sample: Sample) {
        guard let entry = playing.removeValue(forKey: sample.id) else { return }

        entry.player.stop()
        engine.detach(entry.mixer)
        engine.detach(entry.varispeed)
        engine.detach(entry.timePitch)
        engine.detach(entry.player)

        if playing.isEmpty {
            masterStartTime = nil
            isPlaying = false
        }
    }

    private func adjustAllPlaybackRates() {
        for entry in playing.values {
            applyRate(to: entry)
        }
    }

    private func applyRate(to entry: PlayingSample) {
        let rate = Float(bpm / entry.sample.bpm)
        if pitchLock {
            entry.varispeed.rate = 1.0
            entry.timePitch.rate = rate
        } else {
            entry.varispeed.rate = rate
            entry.timePitch.rate = 1.0
        }
        entry.timePitch.pitch = 0.0
        entry.timePitch.overlap = pitchLock ? 8.0 : 3.0
    }

    private func startAllPlayersInSync() {
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTime(0.1))
        masterStartTime = startTime

        for entry in playing.values {
            entry.player.stop()
            entry.player.reset()
        }
        for entry in playing.values {
            entry.player.scheduleBuffer(entry.buffer, at: startTime, options: [.loops], completionHandler: nil)
        }
        for entry in playing.values {
            entry.player.play()
        }
    }

    func stopAllPlayers() {
        isPlaying = false
        masterStartTime = nil
        for entry in playing.values {
            entry.player.stop()
            entry.player.reset()
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
}

// MARK: - Test hooks
//
// Test-only accessors. Gated to DEBUG so the production binary doesn't ship
// them and so internal state stays private to production callers. The test
// bundle is built in Debug, so these are available to XCTest.

#if DEBUG
extension AudioManager {
    func testPlayer(for sampleId: Int) -> AVAudioPlayerNode? {
        playing[sampleId]?.player
    }

    func getPlaybackRate(for sample: Sample) -> Float {
        Float(bpm / sample.bpm)
    }

    func getSamplePhase(for sampleId: Int) -> Double {
        guard let entry = playing[sampleId],
              let playerTime = entry.player.lastRenderTime,
              let startTime = masterStartTime,
              playerTime.isSampleTimeValid else { return 0 }

        let elapsed = playerTime.timeIntervalSince(startTime)
        let beatsPerSecond = bpm / 60.0
        return (elapsed * beatsPerSecond).truncatingRemainder(dividingBy: 1.0)
    }

    func getSampleRate(for sampleId: Int) -> Float {
        playing[sampleId]?.varispeed.rate ?? 0
    }
}
#endif

// MARK: - AVAudioTime helpers

extension AVAudioTime {
    func timeIntervalSince(_ other: AVAudioTime) -> TimeInterval {
        let diff = Int64(bitPattern: hostTime) - Int64(bitPattern: other.hostTime)

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let numer = Double(timebase.numer)
        let denom = Double(timebase.denom)
        return Double(diff) * numer / (denom * Double(NSEC_PER_SEC))
    }
}
