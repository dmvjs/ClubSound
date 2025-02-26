import Foundation
@testable import TypeBeat

/// A mock beat clock for testing that allows manual control of the current beat
class MockBeatClock: BeatClock {
    /// The manually set current beat, if any
    private var manualCurrentBeat: Double?
    
    /// Set the current beat manually for testing
    /// - Parameter beat: The beat to set
    func setCurrentBeat(_ beat: Double) {
        manualCurrentBeat = beat
    }
    
    /// Reset the manual beat setting
    func resetManualBeat() {
        manualCurrentBeat = nil
    }
    
    /// Get the current beat (overridden to return the manual beat if set)
    override func currentBeat() -> Double {
        return manualCurrentBeat ?? super.currentBeat()
    }
} 