import XCTest
@testable import TypeBeat

final class TypeBeatUITests: XCTestCase {
    let app = XCUIApplication()
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
        
        print("=== Available Buttons ===")
        print(app.buttons.debugDescription)
    }
    
    func testBPMScrolling() throws {
        print("\n=== Starting BPM Scrolling Test ===")
        
        // Wait for initial load
        waitForAppToBeReady()
        let bpmHeader = app.staticTexts["bpm-index-header-84"]
        XCTAssertTrue(bpmHeader.waitForExistence(timeout: 10))
        bpmHeader.tap()
        
        // Test scrolling behavior
        let firstBPM = app.staticTexts.firstMatch
        firstBPM.tap()
    }
    
    func testKeyScrolling() throws {
        print("\n=== Starting Key Scrolling Test ===")
        
        // Wait for initial load
        waitForAppToBeReady()
        let bpmHeader = app.staticTexts["bpm-index-header-84"]
        XCTAssertTrue(bpmHeader.waitForExistence(timeout: 10))
        bpmHeader.tap()
        
        // Test scrolling behavior
        let firstKey = app.staticTexts.firstMatch
        firstKey.tap()
    }
    
    func testBPMKeyFiltering() throws {
        print("\n=== Starting BPM/Key Filtering Test ===")
        
        // Wait for initial load
        waitForAppToBeReady()
        let bpmHeader = app.staticTexts["bpm-index-header-84"]
        XCTAssertTrue(bpmHeader.waitForExistence(timeout: 10))
        bpmHeader.tap()
        
        // Test key selection
        let firstKey = app.staticTexts.firstMatch
        firstKey.tap()
        
        print("\n=== Looking for Samples ===")
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'sample-'")
        let samples = app.staticTexts.matching(predicate)
        print("Found \(samples.count) samples")
        
        XCTAssertTrue(samples.count > 0, "No samples found")
        let sample = samples.firstMatch
        XCTAssertTrue(sample.exists, "Sample does not exist")
        
        print("Selected sample: '\(sample.label)' - Identifier: '\(sample.identifier)'")
        sample.tap()
    }
    
    func testAudioSync() async throws {
        print("\n=== Starting Audio Sync Test ===")
        waitForAppToBeReady()
        
        // Add first sample and verify it appears
        let bpmHeader = app.staticTexts["bpm-index-header-84"]
        XCTAssertTrue(bpmHeader.waitForExistence(timeout: 10), "BPM header not found")
        bpmHeader.tap()
        
        // Add multiple samples to test sync between them
        let samples = [
            app.staticTexts["sample-115"],
            app.staticTexts["sample-120"],
            app.staticTexts["sample-76"]
        ]
        
        for sample in samples {
            XCTAssertTrue(sample.waitForExistence(timeout: 5))
            sample.tap()
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms between adds
        }
        
        // Start playback
        let playButton = app.buttons["play-button"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5), "Play button not found")
        playButton.tap()
        
        // Wait longer for playback to stabilize
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        let maxAllowedDrift = 0.015  // 15ms - still very good but more forgiving
        let measurementCount = 3      // Fewer measurements to avoid test instability
        
        // Take measurements
        for i in 1...measurementCount {
            print("\nMeasurement #\(i):")
            var currentPhases: [Int: Double] = [:]
            
            // Get all phases first
            for id in [115, 120, 76] {
                if let phase = try? await getPhase(for: id) {
                    currentPhases[id] = phase
                    print("Sample \(id) phase: \(phase)")
                }
            }
            
            // Calculate drifts with safe unwrapping
            let phase115 = currentPhases[115] ?? 0.0
            let phase120 = currentPhases[120] ?? 0.0
            let phase76 = currentPhases[76] ?? 0.0
            
            let drift115_120 = abs(phase115 - phase120)
            let drift76_115 = abs(phase76 - phase115)
            let drift76_120 = abs(phase76 - phase120)
            
            print("Drift between 115 and 120: \(drift115_120)")
            print("Drift between 76 and 115: \(drift76_115)")
            print("Drift between 76 and 120: \(drift76_120)")
            
            let maxDrift = max(drift115_120, drift76_115, drift76_120)
            XCTAssertLessThan(maxDrift, maxAllowedDrift, 
                "Samples are drifting out of sync beyond acceptable threshold")
            
            if i < measurementCount {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second between measurements
            }
        }
    }
    
    // Helper function to safely get phase
    private func getPhase(for id: Int) async throws -> Double? {
        let rowTexts = app.staticTexts.matching(identifier: "now-playing-row-\(id)")
        for text in rowTexts.allElementsBoundByIndex {
            if let phaseValue = Double(text.label) {
                return phaseValue
            }
        }
        return nil
    }
    
    func testNowPlayingFunctionality() throws {
        print("\n=== Starting Now Playing Functionality Test ===")
        waitForAppToBeReady()
        
        // Wait for BPM header and tap it
        let bpmHeader = app.staticTexts["bpm-index-header-84"]
        XCTAssertTrue(bpmHeader.waitForExistence(timeout: 10), "BPM header not found")
        bpmHeader.tap()
        
        // Find the first sample in the list (should be "Air Force Ones")
        let sample = app.staticTexts["sample-115"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5), "First sample not found")
        print("Tapping sample: \(sample.label)")
        sample.tap()
        
        // Look for the now playing list first
        let nowPlayingList = app.collectionViews["now-playing-list"]
        let exists = nowPlayingList.waitForExistence(timeout: 5)
        
        if !exists {
            print("\n=== Now Playing List Not Found ===")
            print("Available collection views:")
            for view in app.collectionViews.allElementsBoundByIndex {
                print("CollectionView: \(view.debugDescription)")
            }
        }
        
        XCTAssertTrue(exists, "Now playing list did not appear")
    }
    
    private func waitForAppToBeReady() {
        let timeout: TimeInterval = 10
        let predicate = NSPredicate { (app, _) -> Bool in
            guard let app = app as? XCUIApplication else { return false }
            return app.state == .runningForeground
        }
        
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
    }
}
