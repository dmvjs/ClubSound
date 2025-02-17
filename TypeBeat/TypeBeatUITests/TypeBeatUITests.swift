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
    
    func testAudioSync() throws {
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
        }
        
        // Start playback
        let playButton = app.buttons["play-button"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5), "Play button not found")
        playButton.tap()
        
        // Wait longer for playback to stabilize
        Thread.sleep(forTimeInterval: 3.0)
        
        // Check phase alignment for each sample
        var initialPhases: [Int: Double] = [:]
        var maxDrift: Double = 0.0
        let sampleIds = [115, 120, 76]
        
        // Take multiple measurements over time
        for measurementNum in 1...5 {
            print("\nMeasurement #\(measurementNum):")
            var currentPhases: [Int: Double] = [:]
            
            // Get all phases first
            for id in sampleIds {
                let rowTexts = app.staticTexts.matching(identifier: "now-playing-row-\(id)")
                for text in rowTexts.allElementsBoundByIndex {
                    if let phaseValue = Double(text.label) {
                        currentPhases[id] = phaseValue
                        print("Sample \(id) phase: \(phaseValue)")
                        break
                    }
                }
            }
            
            // On first measurement, store initial phase differences
            if measurementNum == 1 {
                initialPhases = currentPhases
            } else {
                // Compare current phase differences with initial ones
                for id in sampleIds {
                    for otherId in sampleIds where otherId > id {
                        let initialDelta = abs((initialPhases[id] ?? 0.0) - (initialPhases[otherId] ?? 0.0))
                        let currentDelta = abs((currentPhases[id] ?? 0.0) - (currentPhases[otherId] ?? 0.0))
                        let driftAmount = abs(currentDelta - initialDelta)
                        
                        print("Drift between \(id) and \(otherId): \(driftAmount)")
                        maxDrift = max(maxDrift, driftAmount)
                    }
                }
            }
            
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Allow for up to 5ms of apparent drift due to UI update timing differences
        XCTAssertLessThan(maxDrift, 0.005, "Samples are drifting out of sync beyond acceptable threshold")
        print("Maximum observed drift: \(maxDrift)")
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
