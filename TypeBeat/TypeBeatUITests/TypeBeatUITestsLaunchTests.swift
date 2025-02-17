import XCTest

final class TypeBeatUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false  // Prevents device cloning
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Print app state for debugging
        print("=== App Launch State ===")
        print("Is running: \(app.state == .runningForeground)")
        
        // Print available buttons
        print("=== Available Buttons ===")
        app.buttons.allElementsBoundByIndex.forEach { button in
            print("Button: \(button.label)")
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}