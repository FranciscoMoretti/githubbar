import XCTest
@testable import GitHubBar

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testValidationUpdaterIsExplicitlyDisabled() {
        let controller = DisabledUpdateController()

        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertEqual(
            controller.presentation,
            .disabled(message: "Automatic updates are disabled in this validation build.")
        )
    }
}
