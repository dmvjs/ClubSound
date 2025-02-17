import XCTest

final class TypeBeatUITests: XCTestCase {
    var app: XCUIApplication!
    
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false  // Prevents device cloning
    }
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Print available buttons for debugging
        print("=== Available Buttons ===")
        app.buttons.allElementsBoundByIndex.forEach { button in
            print("Button: \(button.label)")
        }
    }
    
    override func tearDownWithError() throws {
        if app != nil {
            app.terminate()
            app = nil
        }
        super.tearDown()
    }
    
    func testBPMScrolling() throws {
        // ... existing implementation ...
    }
    
    func testKeyScrolling() throws {
        // ... existing implementation ...
    }
    
    func testBPMKeyFiltering() throws {
        // ... existing implementation ...
    }
    
    func testNowPlayingFunctionality() throws {
        print("\n=== Starting Now Playing Functionality Test ===")
        
        // Wait for the app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "App did not enter running state")
        
        // Wait for BPM headers
        let bpmPredicate = NSPredicate(format: "label MATCHES %@", "\\d+ BPM")
        let bpmTexts = app.staticTexts.matching(bpmPredicate)
        
        print("\n=== Waiting for BPM headers ===")
        let bpmExists = bpmTexts.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(bpmExists, "No BPM headers found after 10 seconds")
        
        // Tap the first BPM header
        let firstBPMHeader = bpmTexts.firstMatch
        firstBPMHeader.tap()
        
        // Wait for samples to load
        Thread.sleep(forTimeInterval: 2.0)
        
        print("\n=== Looking for Samples ===")
        let samples = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH[c] %@ AND length:(label) > 2", "sample-"))
        let sampleCount = samples.count
        print("Found \(sampleCount) samples")
        
        // Get first sample and tap it directly instead of iterating through all
        let firstSample = samples.element(boundBy: 0)
        print("Selected sample: '\(firstSample.label)' - Identifier: '\(firstSample.identifier)'")
        firstSample.tap()
        
        // Wait for Now Playing to appear
        Thread.sleep(forTimeInterval: 1.0)
        
        // Add just 2 samples
        for i in 0...1 {
            let sample = samples.element(boundBy: i)
            print("Tapping sample: '\(sample.label)'")
            sample.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        
        // Wait for the list to populate
        Thread.sleep(forTimeInterval: 2.0)
        
        // Find the cell containing our sample
        let cells = app.cells
        XCTAssertTrue(cells.count > 0, "No cells found in the list")
        
        // Get the first cell
        let firstCell = cells.firstMatch
        XCTAssertTrue(firstCell.exists, "First cell not found")
        
        // Perform the swipe
        let start = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let finish = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: finish)
        
        // Give the swipe animation time to complete
        Thread.sleep(forTimeInterval: 1.0)
        
        // Tap where the delete button should be (right edge of the cell)
        let deleteCoordinate = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        deleteCoordinate.tap()
        
        // Verify deletion
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(cells.count < 2, "Cell was not deleted")
    }
}