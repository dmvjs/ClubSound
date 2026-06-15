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

    private static let bpmRotation: [Double] = [84, 94, 102]
    private static let swapsPerBPM: Int = 5
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
    private var currentPair: [Sample] = []
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
        currentPair = []
        persist()
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

    /// Adopts whatever's currently playing into `currentPair`:
    ///   0 samples → bail (caller should never get here, defensive)
    ///   1 sample  → keep as song 1, add a partner at the next wrap
    ///   2 samples → adopt as-is
    ///   >2        → trim extras at half-beat intervals from next wrap
    private func adoptInitialSamples() async {
        let initial = audioManager.activeSamples
        switch initial.count {
        case 0:
            return
        case 1:
            currentPair = initial
            await waitUntilLoopWrap()
            guard !Task.isCancelled, isEnabled else { return }
            let pool = unplayedPool(at: audioManager.bpm, excluding: Set(initial.map(\.id)))
            if let partner = HarmonicPairSelector.pickPair(from: pool).first {
                await audioManager.addSampleToPlay(partner)
                audioManager.setVolume(for: partner, volume: Self.targetVolume)
                markPlayed([partner])
                currentPair.append(partner)
            }
        case 2:
            currentPair = initial
        default:
            currentPair = Array(initial.prefix(2))
            let extras = Array(initial.suffix(from: 2))
            await waitUntilLoopWrap()
            guard !Task.isCancelled, isEnabled else { return }
            let beat = 60.0 / audioManager.bpm
            for (i, sample) in extras.enumerated() {
                try? await Task.sleep(for: .seconds(beat * 0.5 * Double(i + 1)))
                guard !Task.isCancelled, isEnabled else { return }
                audioManager.removeSampleFromPlay(sample)
            }
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

        let isTransition = swapsAtBPM >= Self.swapsPerBPM - 1
        let nextIdx = (bpmIndex + 1) % Self.bpmRotation.count
        let pickBPM = isTransition ? Self.bpmRotation[nextIdx] : audioManager.bpm
        if isTransition { ensureSufficientPool(at: pickBPM) }

        let pool = unplayedPool(at: pickBPM, excluding: Set(currentPair.map(\.id)))
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

        for sample in incoming { await audioManager.addSampleToPlay(sample) }
        guard !Task.isCancelled, isEnabled else { return }
        markPlayed(incoming)
        fadeIn(incoming, to: Self.targetVolume, over: loopRemainingSeconds())

        await waitUntilBeatsBeforeLoopEnd(4)
        guard !Task.isCancelled, isEnabled else { return }
        if let first = currentPair.first { audioManager.removeSampleFromPlay(first) }

        await waitUntilBeatsBeforeLoopEnd(2)
        guard !Task.isCancelled, isEnabled else { return }
        if currentPair.count > 1 { audioManager.removeSampleFromPlay(currentPair[1]) }

        await waitUntilLoopWrap()
        guard !Task.isCancelled, isEnabled else { return }
        currentPair = incoming
        if isTransition {
            bpmIndex = nextIdx
            audioManager.bpm = Self.bpmRotation[bpmIndex]
            swapsAtBPM = 0
        } else {
            swapsAtBPM += 1
        }
        persist()
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
            if remaining <= seconds + 0.04 { return }
            let sleep = max(0.02, min(remaining - seconds, 0.2))
            try? await Task.sleep(for: .seconds(sleep))
        }
    }

    private func waitUntilBeatsBeforeLoopEnd(_ beats: Double) async {
        await waitUntilSecondsBeforeLoopEnd(beats * 60.0 / audioManager.bpm)
    }

    private func waitUntilLoopWrap() async {
        let before = audioManager.loopProgress()
        while !Task.isCancelled, isEnabled {
            try? await Task.sleep(for: .seconds(0.04))
            let now = audioManager.loopProgress()
            if now < before - 0.3 { return }
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
