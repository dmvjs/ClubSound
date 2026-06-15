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
    var masterVolume: Float = 0.69 {
        didSet { engine.mainMixerNode.outputVolume = masterVolume }
    }

    /// Mirrors `AVAudioSession.outputVolume` (the system media-volume slider /
    /// hardware rocker), updated via KVO. Views read this directly to drive
    /// the low-volume warning glow on the play button.
    var outputVolume: Float = AVAudioSession.sharedInstance().outputVolume

    /// Severity level for the play-button volume badge. Tuned for a 16-step
    /// iPhone speaker (each notch ≈ 0.0625):
    ///   .muted — exactly zero (no audio)              → red, slashed-speaker
    ///   .low   — first notch only (≤ 0.07 ≈ 1/16)    → yellow, one-wave
    ///   .ok    — anything louder                      → no badge
    /// Bluetooth/AirPods routes may use 32- or 64-step granularity, in which
    /// case more than one notch can land in the yellow band.
    enum VolumeBadge { case muted, low, ok }
    var volumeBadge: VolumeBadge {
        switch outputVolume {
        case ...0.005: .muted
        case ...0.07:  .low
        default:       .ok
        }
    }

    private var volumeObservation: NSKeyValueObservation?

    /// The samples currently in the now-playing strip, in the order they were
    /// added. Views observe this directly; it survives view-tree rebuilds
    /// (e.g. on language change) because it lives in the @MainActor singleton.
    private(set) var activeSamples: [Sample] = []

    /// Per-sample mixer volume (0...1), kept in sync with the mixer node so
    /// view sliders survive view-tree rebuilds.
    private(set) var volumes: [Int: Float] = [:]

    /// Maximum number of simultaneously playing samples.
    static let maxSimultaneousSamples = 4

    private let beatsPerBar = 4.0
    private let totalBars = 16.0
    /// Seconds per master loop iteration (64 beats at the current tempo).
    /// Internal so AutoDJ and NowPlayingCoordinator can compute remaining
    /// time and elapsed-playback positions against the same clock.
    var masterLoopDuration: TimeInterval {
        beatsPerBar * totalBars * 60.0 / bpm
    }

    /// AutoDJ scheduler — owns the auto-mix toggle, hamiltonian rotation
    /// state, and the swap task. Created in `init` so it can take a
    /// back-reference to self.
    private(set) var autoDJ: AutoDJ!

    /// Bridges audio state to the lock-screen / Control-Center Now Playing
    /// widget and routes remote commands back into playback.
    private var nowPlayingCoordinator: NowPlayingCoordinator!

    private let engine = AVAudioEngine()
    private var playing: [Int: PlayingSample] = [:]

    /// Audio sample-clock position at which the current playback session
    /// began. Elapsed-time queries (loopProgress, phase calculations) measure
    /// against this — sample time doesn't drift relative to what the audio
    /// thread is rendering, unlike host time.
    private var masterStartSample: AVAudioFramePosition?

    private var sampleRate: Double {
        engine.outputNode.outputFormat(forBus: 0).sampleRate
    }

    /// Captures a synchronized (host, sample) pair from the engine's last
    /// render cycle, offset by `leadSeconds` into the future. Schedule via
    /// the returned AVAudioTime (host-clock based — works for any node,
    /// including fresh AVAudioPlayerNodes whose internal sample-time
    /// timeline starts at zero); measure elapsed via the returned sample
    /// position. Both reference the same render-cycle moment, so they're
    /// internally consistent.
    private func futureStart(leadSeconds: TimeInterval = 0.02)
        -> (time: AVAudioTime, sample: AVAudioFramePosition)? {
        guard let renderTime = engine.outputNode.lastRenderTime,
              renderTime.isSampleTimeValid else { return nil }
        let leadHost = AVAudioTime.hostTime(forSeconds: leadSeconds)
        let leadFrames = AVAudioFramePosition(sampleRate * leadSeconds)
        let time = AVAudioTime(hostTime: renderTime.hostTime + leadHost)
        let sample = renderTime.sampleTime + leadFrames
        return (time, sample)
    }

    private struct PlayingSample {
        let sample: Sample
        let player: AVAudioPlayerNode
        let mixer: AVAudioMixerNode
        let varispeed: AVAudioUnitVarispeed
        let timePitch: AVAudioUnitTimePitch
        let delay: AVAudioUnitDelay
        let buffer: AVAudioPCMBuffer
    }

    private init() {
        setupAudioSession()
        setupEngine()
        engine.prepare()
        try? engine.start()
        observeOutputVolume()
        // AutoDJ takes a back-reference to self for tempo/sample mutations.
        // NowPlayingCoordinator observes both to drive the system widget.
        autoDJ = AutoDJ(audioManager: self)
        nowPlayingCoordinator = NowPlayingCoordinator(audioManager: self, autoDJ: autoDJ)
    }

    private func observeOutputVolume() {
        let session = AVAudioSession.sharedInstance()
        outputVolume = session.outputVolume
        // KVO callback may fire off the main thread; bounce to MainActor
        // because `outputVolume` is observable UI state.
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let newVolume = session.outputVolume
            Task { @MainActor [weak self] in
                self?.outputVolume = newVolume
            }
        }
    }

    /// Stops playback and removes every active sample.
    func reset() {
        stopAllPlayers()
        for entry in playing.values {
            engine.detach(entry.mixer)
            engine.detach(entry.varispeed)
            engine.detach(entry.timePitch)
            engine.detach(entry.delay)
            engine.detach(entry.player)
        }
        playing.removeAll()
        activeSamples.removeAll()
        volumes.removeAll()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
            // No `.mixWithOthers` — that flag opts out of being the primary
            // audio app, which suppresses the Now Playing widget on the
            // lock screen / Control Center. For a DJ app we want primary
            // status so play/pause and metadata show up in the system UI.
            try session.setCategory(.playback, mode: .default)
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
        guard isPlaying,
              let startSample = masterStartSample,
              let renderTime = engine.outputNode.lastRenderTime,
              renderTime.isSampleTimeValid else { return 0.0 }
        let elapsed = Double(renderTime.sampleTime - startSample) / sampleRate
        return elapsed.truncatingRemainder(dividingBy: masterLoopDuration) / masterLoopDuration
    }

    func addSampleToPlay(_ sample: Sample) async {
        // Enforce the 4-sample limit + dedup at the audio layer so views can't
        // diverge from engine state.
        guard activeSamples.count < Self.maxSimultaneousSamples,
              !activeSamples.contains(where: { $0.id == sample.id }) else { return }

        // Insert into the now-playing list immediately for snappy UI feedback;
        // roll back if the audio file fails to load.
        activeSamples.append(sample)
        volumes[sample.id] = 0.0

        // File I/O happens off-main so we don't block the audio/UI thread.
        guard let buffer = await Self.loadBuffer(for: sample) else {
            activeSamples.removeAll { $0.id == sample.id }
            volumes.removeValue(forKey: sample.id)
            return
        }

        let delay = AVAudioUnitDelay()
        delay.wetDryMix = 0      // bypassed during normal playback
        delay.feedback = 0
        delay.delayTime = 0

        let entry = PlayingSample(
            sample: sample,
            player: AVAudioPlayerNode(),
            mixer: AVAudioMixerNode(),
            varispeed: AVAudioUnitVarispeed(),
            timePitch: AVAudioUnitTimePitch(),
            delay: delay,
            buffer: buffer
        )

        engine.attach(entry.player)
        engine.attach(entry.mixer)
        engine.attach(entry.varispeed)
        engine.attach(entry.timePitch)
        engine.attach(entry.delay)

        engine.connect(entry.player, to: entry.varispeed, format: buffer.format)
        engine.connect(entry.varispeed, to: entry.timePitch, format: buffer.format)
        engine.connect(entry.timePitch, to: entry.delay, format: buffer.format)
        engine.connect(entry.delay, to: entry.mixer, format: buffer.format)
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
        guard let start = futureStart() else { return }
        let rate = bpm / entry.sample.bpm

        let buffer = entry.buffer
        let bufferFrames = AVAudioFramePosition(buffer.frameLength)
        var frameOffset: AVAudioFramePosition = 0

        if let masterStartSample, start.sample > masterStartSample {
            let elapsed = Double(start.sample - masterStartSample) / sampleRate
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
            player.scheduleBuffer(slice, at: start.time, completionHandler: nil)
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        } else {
            // Either at a loop boundary, or buffer-slice fell through — start clean.
            player.scheduleBuffer(buffer, at: start.time, options: [.loops], completionHandler: nil)
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

    func setVolume(for sample: Sample, volume: Float) {
        volumes[sample.id] = volume
        playing[sample.id]?.mixer.outputVolume = volume
    }

    func removeSampleFromPlay(_ sample: Sample) {
        // Remove from the now-playing UI immediately. The audio entry stays
        // in `playing` until its echo tail finishes so the engine graph
        // keeps rendering through the fade-out.
        activeSamples.removeAll { $0.id == sample.id }
        volumes.removeValue(forKey: sample.id)

        guard let entry = playing[sample.id] else { return }

        // DJ outro: backspin into a half-beat echo tail, master tempo
        // untouched so the surviving samples keep the grid.
        //
        // Phase 1 — backspin: a randomized cubic-bezier velocity envelope
        // takes varispeed.rate from the sample's current rate, slingshots
        // it UP to a peak around 1.4–2.5× (hand pushing the platter
        // forward to wind up), then crashes it to varispeed's floor of
        // 0.25 (the yank-back). The lift happens because P1.y goes
        // negative: in our rate formula `start + (floor − start) * curve`,
        // a negative curve value inverts the sign and lifts the rate
        // ABOVE startRate before the cubic term hauls it back to 1
        // (= floor). Player keeps feeding the chain so the delay buffer
        // captures the whole slingshot + crash as a warbling tail.
        //
        // Phase 2 — echo tail: stop the player, flip delay fully wet, ramp
        // the mixer to silence over the tail.
        let beat = 60.0 / bpm
        // Snappy range — feels like a flick of the wrist, not a slow brake.
        let backspinDuration = beat * Double.random(in: 0.35...0.65)
        // P1.y negative → curve dips below 0 → rate lifts above start.
        // Range tuned so peak rate lands roughly between 1.4× and 2.5×.
        // P2.y mid-low → return ramps gently before the cubic crash to 1.
        let p1y = Float.random(in: -5.0 ... -1.5)
        let p2y = Float.random(in: 0.10 ... 0.45)
        let backspinFloor: Float = 0.25   // AVAudioUnitVarispeed minimum
        let backspinCeiling: Float = 4.0  // AVAudioUnitVarispeed maximum
        let startRate = entry.varispeed.rate
        let delayTime = beat / 2          // half-beat echo (sync to grid)
        let feedback: Float = 55          // each repeat ≈ 55% of the previous
        let tailSeconds = delayTime * 5   // ~5 echoes before silence
        let id = sample.id

        Task { @MainActor in
            let steps = max(12, Int(backspinDuration * 60))    // ~60 Hz update
            let stepDuration = backspinDuration / Double(steps)
            for i in 1...steps {
                let t = Float(i) / Float(steps)
                let u = 1 - t
                // Cubic bezier y(t) with P0.y=0, P3.y=1. Negative P1.y
                // lets the curve overshoot below zero mid-flight.
                let curve = 3 * u * u * t * p1y + 3 * u * t * t * p2y + t * t * t
                let rate = startRate + (backspinFloor - startRate) * curve
                entry.varispeed.rate = max(backspinFloor, min(backspinCeiling, rate))
                try? await Task.sleep(for: .seconds(stepDuration))
            }

            entry.delay.delayTime = delayTime
            entry.delay.feedback = feedback
            entry.delay.lowPassCutoff = 5000                   // warm/vintage tape feel
            entry.delay.wetDryMix = 100                        // wet only — dry sample has stopped
            entry.player.stop()
            rampMixer(entry.mixer, to: 0, over: tailSeconds)

            try? await Task.sleep(for: .seconds(tailSeconds + 0.1))
            guard let pending = playing.removeValue(forKey: id) else { return }
            pending.player.stop()
            engine.detach(pending.mixer)
            engine.detach(pending.varispeed)
            engine.detach(pending.timePitch)
            engine.detach(pending.delay)
            engine.detach(pending.player)

            if playing.isEmpty {
                masterStartSample = nil
                isPlaying = false
            }
        }
    }

    /// Smoothly ramps `mixer.outputVolume` from its current value to
    /// `target` over `duration` seconds via short timed steps. Used to feather
    /// in delay-echo tails on delete instead of cutting the audio.
    private func rampMixer(_ mixer: AVAudioMixerNode, to target: Float, over duration: TimeInterval) {
        let steps = max(8, Int(duration * 30))           // ~30 Hz update
        let stepDuration = duration / Double(steps)
        let startVolume = mixer.outputVolume
        Task { @MainActor in
            for i in 1...steps {
                let t = Float(i) / Float(steps)
                mixer.outputVolume = startVolume + (target - startVolume) * t
                try? await Task.sleep(for: .seconds(stepDuration))
            }
            mixer.outputVolume = target
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
        guard let start = futureStart() else { return }
        masterStartSample = start.sample

        for entry in playing.values {
            entry.player.stop()
            entry.player.reset()
        }
        for entry in playing.values {
            entry.player.scheduleBuffer(entry.buffer, at: start.time, options: [.loops], completionHandler: nil)
        }
        for entry in playing.values {
            entry.player.play()
        }
    }

    func stopAllPlayers() {
        isPlaying = false
        masterStartSample = nil
        for entry in playing.values {
            entry.player.stop()
            entry.player.reset()
        }
    }

    func play() {
        isPlaying = true
        startAllPlayersInSync()
    }

    /// Play-button entry point with sensible fills:
    ///
    /// 1. If no samples are loaded, picks two harmonically-related samples
    ///    (same key) at the active tempo and queues them. Tempo 69 has no
    ///    catalog samples, so falls through to 84.
    /// 2. If samples are loaded but every volume is silent, lifts them all
    ///    to just-above-half so the user actually hears something on the
    ///    first tap. Volumes the user has already moved are left alone.
    /// 3. Starts playback.
    func playWithDefaults() async {
        if activeSamples.isEmpty {
            await loadDefaultPair()
        }

        let silenceThreshold: Float = 0.05
        let defaultVolume: Float = 0.6
        if !activeSamples.isEmpty,
           activeSamples.allSatisfy({ (volumes[$0.id] ?? 0) < silenceThreshold }) {
            for sample in activeSamples {
                setVolume(for: sample, volume: defaultVolume)
            }
        }

        play()
    }

    /// Picks two samples in the same key at the active tempo and queues them.
    /// Falls back to two random samples in the tempo bucket if no key has
    /// two available at once.
    private func loadDefaultPair() async {
        let targetBPM: Double = (bpm == 69) ? 84 : bpm
        let pool = TypeBeat.samples.filter { $0.bpm == targetBPM }
        guard !pool.isEmpty else { return }

        let byKey = Dictionary(grouping: pool, by: \.key)
        let pair: [Sample]
        if let twoInOneKey = byKey.values.filter({ $0.count >= 2 }).randomElement() {
            pair = Array(twoInOneKey.shuffled().prefix(2))
        } else {
            // Edge case: every key has only one sample at this tempo.
            // Fall back to any two at the same tempo.
            pair = Array(pool.shuffled().prefix(2))
        }

        for sample in pair {
            await addSampleToPlay(sample)
        }
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
              let startSample = masterStartSample,
              playerTime.isSampleTimeValid else { return 0 }

        let elapsed = Double(playerTime.sampleTime - startSample) / sampleRate
        let beatsPerSecond = bpm / 60.0
        return (elapsed * beatsPerSecond).truncatingRemainder(dividingBy: 1.0)
    }

    func getSampleRate(for sampleId: Int) -> Float {
        playing[sampleId]?.varispeed.rate ?? 0
    }
}
#endif
