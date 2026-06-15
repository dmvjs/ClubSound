import Foundation

/// Picks pairs of samples whose keys form musically compatible intervals.
/// Pure functions — no audio engine, no UI, no global state, trivially
/// testable in isolation from a `[Sample]` pool.
///
/// Selection strategy: ~10% of calls return a fully-random pair regardless
/// of key ("wildcard" — keeps long mixes from feeling formulaic). The other
/// ~90% shuffle a weighted list of compatible intervals and walk it,
/// returning the first viable match.
enum HarmonicPairSelector {
    /// Compatible intervals between paired samples, in semitones. Repetition
    /// acts as weight — each pick shuffles this list and the first viable
    /// entry wins, so an interval's "win probability" equals its share of
    /// the array. Strong consonances appear 2×; spicier intervals appear 1×.
    ///
    ///   0 ×2 — unison (same key)
    ///   5 ×2 — perfect fourth (subdominant)
    ///   7 ×2 — perfect fifth (dominant)
    ///   3 ×2 — minor third (relative minor of a major root)
    ///   9 ×2 — major sixth (relative major of a minor root)
    ///   4 ×1 — major third
    ///   8 ×1 — minor sixth
    ///   2 ×1 — major second (step-up modulation)
    ///   6 ×1 — tritone (chromatic mediant tension)
    ///  10 ×1 — minor seventh (modal color)
    static let intervals: [Int] = [
        0, 0, 5, 5, 7, 7, 3, 3, 9, 9,
        4, 8, 2, 6, 10,
    ]

    /// Probability of bypassing harmonic filtering and grabbing any two
    /// samples. Sprinkles surprise into otherwise-tidy harmonic rotations.
    static let wildcardProbability: Double = 0.10

    /// Returns two samples whose keys form one of the configured intervals,
    /// or empty if `pool` has fewer than two samples.
    static func pickPair(from pool: [Sample]) -> [Sample] {
        guard pool.count >= 2 else { return [] }

        if Double.random(in: 0..<1) < wildcardProbability {
            return Array(pool.shuffled().prefix(2))
        }

        let byKey = Dictionary(grouping: pool, by: \.key)
        for offset in intervals.shuffled() {
            for seedKey in byKey.keys.shuffled() {
                guard let seedBucket = byKey[seedKey] else { continue }
                if offset == 0 {
                    if seedBucket.count >= 2 {
                        return Array(seedBucket.shuffled().prefix(2))
                    }
                } else {
                    let partnerKey = transposeKey(seedKey, by: offset)
                    if let partnerBucket = byKey[partnerKey],
                       let seed = seedBucket.randomElement(),
                       let partner = partnerBucket.randomElement(),
                       seed.id != partner.id {
                        return [seed, partner]
                    }
                }
            }
        }

        // Pool is non-empty but no compatible pair fit — fall back to any
        // two so the caller never gets back an empty result with samples
        // available.
        return Array(pool.shuffled().prefix(2))
    }

    /// Adds `semitones` to `root`, wrapping within the chromatic octave.
    /// Negative semitones are handled correctly via the +12 modulus.
    static func transposeKey(_ root: MusicKey, by semitones: Int) -> MusicKey {
        let cases = MusicKey.allCases
        let rootIdx = cases.firstIndex(of: root)!
        let newIdx = (rootIdx + semitones % 12 + 12) % 12
        return cases[newIdx]
    }
}
