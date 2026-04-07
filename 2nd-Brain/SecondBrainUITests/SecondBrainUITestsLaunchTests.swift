import XCTest

final class SecondBrainUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = SecondBrainUITestLaunchConfiguration.seeded.makeApplication()
        app.launch()
        XCTAssertTrue(app.state == XCUIApplication.State.runningForeground)
    }
}
