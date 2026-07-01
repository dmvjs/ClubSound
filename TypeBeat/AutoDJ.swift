import Foundation
import Observation

/// DJ-style auto-mix scheduler. Adopts the audio engine's current playback,
/// then on every loop swaps in a new harmonically-compatible pair while
/// backspinning the previous pair out 4-then-2 beats before the wrap.
/// Every 5 swaps the master BPM advances through `bpmRotation`.
///
/// State is hamiltonian: a sample is never repeated until every sample at
/// every BPM has been played, with a per-BPM minimum pool to avoid stalling
/// on a sparse tail. The full state (toggle, unplayed IDs, rotation index,
/// swap counter) persists across launches via a single Codable struct.
@MainActor
@Observable
final class AutoDJ {
    // MARK: - Tunable constants

    // nonisolated: immutable Sendable constants referenced from the pure
    // swapDecision default arguments, which are evaluated in a nonisolated
    // context.
    nonisolated private static let bpmRotation: [Double] = [84, 94, 102]
    nonisolated private static let swapsPerBPM: Int = 5
    private static let targetVolume: Float = 0.7
    private static let minPoolPerBPM: Int = 10
    private static let stateKey = "autoDJ.state"

    // MARK: - Persisted state

    /// All AutoDJ state that survives a launch. One Codable struct keeps the
    /// UserDefaults surface to a single key instead of four loose primitives.
    private struct State: Codable {
        var enabled: Bool = true
        var unplayedIDs: Set<Int> = []
        var bpmIndex: Int = 0
        var swapCount: Int = 0
    }

    /// User-facing toggle. `didSet` persists and starts/stops the task.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            persist()
            if isEnabled { start() } else { stop() }
        }
    }

    // MARK: - Private state

    private let audioManager: AudioManager
    private var task: Task<Void, Never>?
    private var unplayedIDs: Set<Int>
    private var bpmIndex: Int
    private var swapsAtBPM: Int

    // MARK: - Init

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
        let state = Self.loadState()
        self.isEnabled = state.enabled
        self.unplayedIDs = state.unplayedIDs.isEmpty
            ? Set(TypeBeat.samples.map(\.id))
            : state.unplayedIDs
        self.bpmIndex = min(max(state.bpmIndex, 0), Self.bpmRotation.count - 1)
        self.swapsAtBPM = max(state.swapCount, 0)
        if isEnabled { start() }
    }

    // MARK: - Persistence

    private static func loadState() -> State {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return State() }
        return state
    }

    private func persist() {
        let state = State(
            enabled: isEnabled,
            unplayedIDs: unplayedIDs,
            bpmIndex: bpmIndex,
            swapCount: swapsAtBPM
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    // MARK: - Lifecycle

    /// Every press restarts the cycle from the user's current tempo. The
    /// hamiltonian unplayed set persists across sessions, but the rotation
    /// index + swap count snap to "now" so the user doesn't resume into a
    /// stale BPM.
    private func start() {
        if let idx = Self.bpmRotation.firstIndex(of: audioManager.bpm) {
            bpmIndex = idx
        } else {
            audioManager.bpm = Self.bpmRotation[bpmIndex]
        }
        swapsAtBPM = 0
        ensureSufficientPool(at: audioManager.bpm)
        persist()

        task?.cancel()
        task = Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        persist()
    }

    // MARK: - Rotation decision (pure)

    /// The bucket/transition decision for a single swap. Pure and isolated
    /// from loop timing + the audio engine so the "exactly `swapsPerBPM` sets
    /// per tempo before the master BPM advances" invariant is unit-testable.
    struct SwapDecision: Equatable {
        /// True when this swap rolls the master tempo to the next BPM.
        let isTransition: Bool
        /// `bpmRotation` index the incoming pair is drawn from (and the master
        /// tempo that pair ends up playing at once the wrap completes).
        let pickIndex: Int
        /// `bpmRotation` index the rotation lands on after a transition commit.
        let nextIndex: Int
    }

    /// `swapsAtBPM` counts the non-transition swaps already completed at the
    /// current BPM. Counting the entry pair as set 1, the rotation plays the
    /// entry pair plus `swapsPerBPM - 1` fresh same-tempo swaps (sets 2…N),
    /// and the swap that reaches `swapsPerBPM - 1` is the transition that
    /// brings in the next tempo — i.e. exactly `swapsPerBPM` sets per tempo.
    static func swapDecision(swapsAtBPM: Int,
                             bpmIndex: Int,
                             swapsPerBPM: Int = AutoDJ.swapsPerBPM,
                             rotationCount: Int = AutoDJ.bpmRotation.count) -> SwapDecision {
        let isTransition = swapsAtBPM >= swapsPerBPM - 1
        let nextIndex = (bpmIndex + 1) % rotationCount
        let pickIndex = isTransition ? nextIndex : bpmIndex
        return SwapDecision(isTransition: isTransition, pickIndex: pickIndex, nextIndex: nextIndex)
    }

    // MARK: - Main loop

    private func run() async {
        // Arm only — auto waits for the user to press play, doesn't trigger
        // it. Polling at 200 ms is fine; swap timing measures off the sample
        // clock, not this loop.
        while !audioManager.isPlaying {
            guard !Task.isCancelled, isEnabled else { return }
            try? await Task.sleep(for: .seconds(0.2))
        }

        await adoptInitialSamples()

        while !Task.isCancelled, isEnabled {
            await runSwapCycle()
        }
    }

    /// Trim any extras above two so the next swap cycle can add its
    /// incoming pair without hitting the 4-sample cap. 0/1/2 samples
    /// already playing is fine — the cycle just treats whatever's
    /// playing as the outgoing pair when its time comes.
    private func adoptInitialSamples() async {
        let initial = audioManager.activeSamples
        if initial.count > 2 {
            await fadeOutAndRemove(Array(initial.suffix(from: 2)), over: 2.0)
        }
    }

    /// Ramps each sample's mixer from its current volume to 0 over
    /// `duration`, then hands off to `removeSampleFromPlay` so the engine
    /// graph cleanup matches the normal removal path.
    private func fadeOutAndRemove(_ samples: [Sample], over duration: TimeInterval) async {
        let steps = max(8, Int(duration * 30))
        let stepDur = duration / Double(steps)
        let starts = samples.map { audioManager.volumes[$0.id] ?? 0 }
        for i in 1...steps {
            let t = Float(i) / Float(steps)
            for (sample, start) in zip(samples, starts) {
                audioManager.setVolume(for: sample, volume: start * (1 - t))
            }
            try? await Task.sleep(for: .seconds(stepDur))
        }
        for sample in samples {
            audioManager.removeSampleFromPlay(sample)
        }
    }

    /// One swap. Spawns next pair 5s before the wrap, fades them up over
    /// that window, backspins outgoing 4-then-2 beats before the wrap, and
    /// promotes incoming at the wrap. The 5th swap of each BPM is also the
    /// transition swap — picks incoming from the next BPM bucket and flips
    /// master `bpm` at the wrap so the next loop is fully on the new tempo.
    private func runSwapCycle() async {
        await waitUntilSecondsBeforeLoopEnd(5.0)
        guard !Task.isCancelled, isEnabled else { return }

        // Resync to the master tempo in case the user tapped a BPM button
        // while auto was running — otherwise the transition rotates from
        // our stale index and can skip the user's current bucket.
        if let idx = Self.bpmRotation.firstIndex(of: audioManager.bpm) {
            bpmIndex = idx
        }

        let decision = Self.swapDecision(swapsAtBPM: swapsAtBPM, bpmIndex: bpmIndex)
        let isTransition = decision.isTransition
        let nextIdx = decision.nextIndex
        let pickBPM = Self.bpmRotation[decision.pickIndex]
        if isTransition { ensureSufficientPool(at: pickBPM) }

        // The pair being handed off IS whatever's playing right now —
        // no tracked state to fall out of sync with reality. If only
        // one sample is playing, only one is removed; if zero, none.
        let outgoing = audioManager.activeSamples

        let pool = unplayedPool(at: pickBPM, excluding: Set(outgoing.map(\.id)))
        let incoming = HarmonicPairSelector.pickPair(from: pool)
        guard !incoming.isEmpty else {
            // Pool depleted mid-rotation — skip ahead to next bucket.
            bpmIndex = nextIdx
            audioManager.bpm = Self.bpmRotation[bpmIndex]
            swapsAtBPM = 0
            ensureSufficientPool(at: audioManager.bpm)
            persist()
            return
        }

        // Tempo transition: a clean, sample-accurate seam, not a swap.
        if isTransition {
            await runTempoSeam(outgoing: outgoing, incoming: incoming, newBPM: pickBPM)
            guard !Task.isCancelled, isEnabled else { return }
            bpmIndex = nextIdx
            swapsAtBPM = 0
            persist()
            return
        }

        // Same-tempo swap: DJ-style crossfade with a backspin + echo outro.
        for sample in incoming { await audioManager.addSampleToPlay(sample) }
        guard !Task.isCancelled, isEnabled else { return }
        markPlayed(incoming)
        fadeIn(incoming, to: Self.targetVolume, over: loopRemainingSeconds())

        await waitUntilBeatsBeforeLoopEnd(4)
        guard !Task.isCancelled, isEnabled else { return }
        if let first = outgoing.first { audioManager.removeSampleFromPlay(first) }

        await waitUntilBeatsBeforeLoopEnd(2)
        guard !Task.isCancelled, isEnabled else { return }
        if outgoing.count > 1 { audioManager.removeSampleFromPlay(outgoing[1]) }

        await waitUntilLoopWrap()
        guard !Task.isCancelled, isEnabled else { return }

        // Belt-and-suspenders: any outgoing still in activeSamples at the
        // wrap means the timed 4/2-beat removes missed (e.g. backgrounded
        // mid-cycle and the awaits overshot). Sweep them now so we don't
        // carry a stale pair into the next cycle and starve incoming on
        // the 4-sample cap.
        for sample in outgoing
            where audioManager.activeSamples.contains(where: { $0.id == sample.id }) {
            audioManager.removeSampleFromPlay(sample)
        }

        swapsAtBPM += 1
        persist()
    }

    /// Tempo transition seam. The outgoing pair plays out to the exact end of
    /// its current loop at the old tempo, then stops; the incoming pair (drawn
    /// from the new BPM bucket) begins on that downbeat at the new tempo. No
    /// fade-in, no backspin, no echo — the hard, grid-locked cut the user
    /// wants only at the A→B seam. The incoming pair is pre-staged silently so
    /// nothing sounds at the old tempo before the seam and there's no file-I/O
    /// latency at the boundary.
    private func runTempoSeam(outgoing: [Sample], incoming: [Sample], newBPM: Double) async {
        for sample in incoming {
            await audioManager.addSampleToPlay(sample, scheduleNow: false)
        }
        guard !Task.isCancelled, isEnabled else { return }
        markPlayed(incoming)

        // Get within scheduling range of the seam, then commit. `untilSeam` is
        // captured before the commit rolls the master clock onto the new loop.
        await waitUntilSecondsBeforeLoopEnd(0.4)
        guard !Task.isCancelled, isEnabled else { return }

        let untilSeam = loopRemainingSeconds()
        audioManager.commitTempoSeam(outgoing: outgoing,
                                     incoming: incoming,
                                     newBPM: newBPM,
                                     volume: Self.targetVolume)

        // Hold past the seam so the next cycle measures against the new loop.
        try? await Task.sleep(for: .seconds(untilSeam + 0.05))
    }

    // MARK: - Pool management

    private func unplayedPool(at bpm: Double, excluding: Set<Int> = []) -> [Sample] {
        TypeBeat.samples.filter {
            $0.bpm == bpm &&
            unplayedIDs.contains($0.id) &&
            !excluding.contains($0.id)
        }
    }

    private func markPlayed(_ samples: [Sample]) {
        for sample in samples { unplayedIDs.remove(sample.id) }
        if unplayedIDs.isEmpty {
            unplayedIDs = Set(TypeBeat.samples.map(\.id))
        }
        persist()
    }

    /// Refills `unplayedIDs` for a BPM that's run dry. Hamiltonian fairness
    /// is enforced globally, but any single bucket dipping below
    /// `minPoolPerBPM` gets a full-catalog top-up so the rotation doesn't
    /// stall on a tail of one or two leftover tracks.
    private func ensureSufficientPool(at bpm: Double) {
        let bucket = TypeBeat.samples.filter { $0.bpm == bpm }
        let count = bucket.lazy.filter { self.unplayedIDs.contains($0.id) }.count
        guard count < Self.minPoolPerBPM else { return }
        for sample in bucket { unplayedIDs.insert(sample.id) }
        persist()
    }

    // MARK: - Timing helpers

    private func loopRemainingSeconds() -> Double {
        max(0, (1.0 - audioManager.loopProgress()) * audioManager.masterLoopDuration)
    }

    private func waitUntilSecondsBeforeLoopEnd(_ seconds: Double) async {
        while !Task.isCancelled, isEnabled {
            let remaining = loopRemainingSeconds()
            if remaining <= seconds + 0.1 { return }
            let sleep = max(0.1, min(remaining - seconds, 0.2))
            try? await Task.sleep(for: .seconds(sleep))
        }
    }

    private func waitUntilBeatsBeforeLoopEnd(_ beats: Double) async {
        await waitUntilSecondsBeforeLoopEnd(beats * 60.0 / audioManager.bpm)
    }

    private func waitUntilLoopWrap() async {
        var last = audioManager.loopProgress()
        while !Task.isCancelled, isEnabled {
            try? await Task.sleep(for: .seconds(0.1))
            let now = audioManager.loopProgress()
            if now < last - 0.3 { return }
            last = now
        }
    }

    // MARK: - Volume ramps

    /// Ramps mixer volumes from 0 to `target` over `duration`, hitting full
    /// volume right at the loop wrap. Fires off a detached Task — caller
    /// doesn't await it; the next swap timing already accounts for the
    /// ramp duration.
    private func fadeIn(_ samples: [Sample], to target: Float, over duration: TimeInterval) {
        let steps = max(8, Int(duration * 30))
        let stepDur = duration / Double(steps)
        Task { @MainActor [weak self] in
            guard let self else { return }
            for i in 1...steps {
                let t = Float(i) / Float(steps)
                for sample in samples {
                    self.audioManager.setVolume(for: sample, volume: target * t)
                }
                try? await Task.sleep(for: .seconds(stepDur))
            }
            for sample in samples {
                self.audioManager.setVolume(for: sample, volume: target)
            }
        }
    }
}

// MARK: - Test hooks

#if DEBUG
extension AutoDJ {
    static var testSwapsPerBPM: Int { swapsPerBPM }
    static var testBPMRotation: [Double] { bpmRotation }

    /// The master tempo of each audible set across `swaps` swaps, starting
    /// from `startIndex` and counting the entry pair already playing as the
    /// first set. Pure mirror of the `runSwapCycle` rotation — same
    /// `swapDecision`, same commit rules — so tests can assert the
    /// "5 sets per tempo before it switches" guarantee without audio or
    /// loop timing.
    static func simulatedSetTempos(startIndex: Int, swaps: Int) -> [Double] {
        var bpmIndex = startIndex
        var swapsAtBPM = 0
        var tempos: [Double] = [bpmRotation[bpmIndex]]   // entry set (set 1)
        for _ in 0..<swaps {
            let decision = swapDecision(swapsAtBPM: swapsAtBPM, bpmIndex: bpmIndex)
            tempos.append(bpmRotation[decision.pickIndex])
            if decision.isTransition {
                bpmIndex = decision.nextIndex
                swapsAtBPM = 0
            } else {
                swapsAtBPM += 1
            }
        }
        return tempos
    }
}
#endif
