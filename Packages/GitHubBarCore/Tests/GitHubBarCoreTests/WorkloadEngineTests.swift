import XCTest
@testable import GitHubBarCore

final class WorkloadEngineTests: XCTestCase {
    func testReviewCountBadgeCapsVisualTextWithoutCappingAccessibilityCount() {
        XCTAssertNil(ReviewCountBadge.text(for: 0))
        XCTAssertEqual(ReviewCountBadge.text(for: 4), "4")
        XCTAssertEqual(ReviewCountBadge.text(for: 57), "9+")
    }

    func testSubscriberImmediatelyReceivesTruthfulEmptyPresentation() async throws {
        let engine = WorkloadEngine(initialState: .empty)
        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()

        let state = try XCTUnwrap(await iterator.next())

        XCTAssertEqual(state, .empty)
        XCTAssertTrue(state.needsYourReview.isEmpty)
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

    func testChangingRepositoryScopeFiltersCanonicalSnapshotWithoutReconciling() async throws {
        let workloadClient = ScopeFilteringWorkloadClient()
        let engine = WorkloadEngine(
            accountConnection: ConnectedTestAccountConnection(),
            workloadClient: workloadClient,
            settingsStore: InMemorySettingsStore(
                settings: AppSettings(selectedLogin: "FranciscoMoretti")
            )
        )

        await engine.send(.launch)
        XCTAssertEqual(await workloadClient.requestCount, 1)

        await engine.send(.selectRepositoryScope(.selected(["REPO-A"])))
        var state = try await currentState(of: engine)
        XCTAssertEqual(state.needsYourReview.map(\.repositoryID), ["REPO-A"])
        XCTAssertEqual(state.reviewCount, 1)
        XCTAssertFalse(state.isRefreshing)
        XCTAssertEqual(await workloadClient.requestCount, 1)

        await engine.send(.selectRepositoryScope(.selected(["REPO-B"])))
        state = try await currentState(of: engine)
        XCTAssertEqual(state.needsYourReview.map(\.repositoryID), ["REPO-B"])
        XCTAssertEqual(state.reviewCount, 1)
        XCTAssertFalse(state.isRefreshing)
        XCTAssertEqual(await workloadClient.requestCount, 1)

        await engine.send(.selectRepositoryScope(.all))
        state = try await currentState(of: engine)
        XCTAssertEqual(state.needsYourReview.map(\.repositoryID), ["REPO-A", "REPO-B"])
        XCTAssertEqual(state.reviewCount, 2)
        XCTAssertFalse(state.isRefreshing)
        XCTAssertEqual(await workloadClient.requestCount, 1)
    }

    func testConfirmingMonitoredAccountPersistsOnlyItsLogin() async throws {
        let settingsStore = InMemorySettingsStore()
        let engine = WorkloadEngine(
            accountConnection: TestAccountConnection(),
            settingsStore: settingsStore
        )
        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        await engine.send(.launch)
        _ = await iterator.next()
        let selectionState = try XCTUnwrap(await iterator.next())
        guard case .selectionRequired = selectionState.accountConnection else {
            return XCTFail("Expected account selection")
        }

        await engine.send(.confirmAccount("FranciscoMoretti"))
        _ = await iterator.next()
        let connectedState = try XCTUnwrap(await iterator.next())
        guard case let .connected(login, _) = connectedState.accountConnection else {
            return XCTFail("Expected connected account")
        }

        XCTAssertEqual(login, "FranciscoMoretti")
        XCTAssertEqual(await settingsStore.load().selectedLogin, "FranciscoMoretti")
    }

    private func currentState(of engine: WorkloadEngine) async throws -> AppPresentationState {
        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()
        return try XCTUnwrap(await iterator.next())
    }
}

private struct TestAccountConnection: AccountConnection {
    func inspect(selectedLogin: String?) async -> AccountConnectionResult {
        guard let selectedLogin else {
            return .selectionRequired([
                AccountCandidate(login: "FranciscoMoretti", hostname: "github.com"),
                AccountCandidate(login: "francisco-acme", hostname: "github.com"),
            ])
        }
        return .connected(
            ResolvedAccount(
                login: selectedLogin,
                hostname: "github.com",
                scopes: ["read:org", "repo"],
                accessCoverage: AccessCoverage(isComplete: true),
                accessToken: GitHubAccessToken("test-token")
            )
        )
    }
}

private struct ConnectedTestAccountConnection: AccountConnection {
    func inspect(selectedLogin: String?) async -> AccountConnectionResult {
        .connected(
            ResolvedAccount(
                login: selectedLogin ?? "FranciscoMoretti",
                hostname: "github.com",
                scopes: ["read:org", "repo"],
                accessCoverage: AccessCoverage(isComplete: true),
                accessToken: GitHubAccessToken("test-token")
            )
        )
    }
}

private actor ScopeFilteringWorkloadClient: GitHubWorkloadClient {
    private(set) var requestCount = 0

    func reconcile(account: ResolvedAccount) async -> WorkloadReconciliationResult {
        requestCount += 1
        return .complete(
            WorkloadSnapshot(
                hostname: account.hostname,
                accountLogin: account.login,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                completeness: .complete,
                availableRepositories: [
                    RepositoryChoice(id: "REPO-A", nameWithOwner: "owner/a"),
                    RepositoryChoice(id: "REPO-B", nameWithOwner: "owner/b"),
                ],
                needsYourReview: [
                    pullRequest(id: "PR-A", repositoryID: "REPO-A", number: 1),
                    pullRequest(id: "PR-B", repositoryID: "REPO-B", number: 2),
                ],
                authoredPullRequests: []
            ),
            .empty
        )
    }

    private func pullRequest(
        id: String,
        repositoryID: String,
        number: Int
    ) -> PullRequestPresentation {
        PullRequestPresentation(
            id: id,
            repositoryID: repositoryID,
            repositoryNameWithOwner: "owner/\(repositoryID.lowercased())",
            number: number,
            title: "Pull request \(number)",
            url: URL(string: "https://github.com/owner/repo/pull/\(number)")!,
            isDraft: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            reviewers: []
        )
    }
}
