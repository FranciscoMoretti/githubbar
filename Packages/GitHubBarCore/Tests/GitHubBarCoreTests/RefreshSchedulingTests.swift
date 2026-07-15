import XCTest
@testable import GitHubBarCore

final class RefreshSchedulingTests: XCTestCase {
    func testAdaptiveRefreshPolicyMatchesCodexBarBoundaries() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(AdaptiveRefreshPolicy.decision(now: now, lastPopoverOpenAt: nil).reason, .longIdle)
        XCTAssertEqual(AdaptiveRefreshPolicy.decision(now: now, lastPopoverOpenAt: now.addingTimeInterval(-300)).reason, .recentInteraction)
        XCTAssertEqual(AdaptiveRefreshPolicy.decision(now: now, lastPopoverOpenAt: now.addingTimeInterval(-301)).reason, .warm)
        XCTAssertEqual(AdaptiveRefreshPolicy.decision(now: now, lastPopoverOpenAt: now.addingTimeInterval(-3_601)).reason, .idle)
        XCTAssertEqual(AdaptiveRefreshPolicy.decision(now: now, lastPopoverOpenAt: now.addingTimeInterval(-14_400)).reason, .longIdle)
        XCTAssertEqual(AdaptiveRefreshPolicy.decision(now: now, lastPopoverOpenAt: now, isConstrained: true).reason, .constrained)
    }
}
