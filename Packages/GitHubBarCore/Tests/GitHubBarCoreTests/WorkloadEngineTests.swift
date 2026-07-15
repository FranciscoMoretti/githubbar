import XCTest
@testable import GitHubBarCore

final class WorkloadEngineTests: XCTestCase {
    func testSubscriberImmediatelyReceivesTruthfulEmptyPresentation() async throws {
        let engine = WorkloadEngine(initialState: .empty)
        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()

        let state = try XCTUnwrap(await iterator.next())

        XCTAssertEqual(state, .empty)
        XCTAssertTrue(state.waitingForReview.isEmpty)
        XCTAssertTrue(state.authoredPullRequests.isEmpty)
        XCTAssertEqual(state.reviewCount, 0)
        XCTAssertEqual(state.reviewCountAccessibilityLabel, "No pull requests waiting for your review")
    }

    func testChangingRepositoryScopePublishesNewPresentation() async throws {
        let engine = WorkloadEngine(initialState: .empty)
        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        await engine.send(.selectRepositoryScope(.selected(["openai/codex"])))
        let state = try XCTUnwrap(await iterator.next())

        XCTAssertEqual(state.repositoryScope, .selected(["openai/codex"]))
    }
}
