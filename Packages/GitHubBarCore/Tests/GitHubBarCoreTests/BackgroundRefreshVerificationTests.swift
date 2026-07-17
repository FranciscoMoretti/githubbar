import XCTest
@testable import GitHubBarCore

final class BackgroundRefreshVerificationTests: XCTestCase {
    func testFiveMinuteRefreshRunsWhileWorkloadSurfaceClosedAndPublishesNewReviewCount() async throws {
        let clock = ManuallyAdvancingRefreshClock(
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let client = ReviewCountWorkloadClient(reviewCounts: [0, 2])
        let engine = WorkloadEngine(
            accountConnection: ConnectedVerificationAccount(),
            workloadClient: client,
            settingsStore: InMemorySettingsStore(
                settings: AppSettings(
                    selectedLogin: "FranciscoMoretti",
                    refreshCadence: .fiveMinutes
                )
            ),
            clock: clock
        )

        await engine.send(.launch)
        await engine.send(.setWorkloadSurfaceOpen(false))
        try await waitUntil { await clock.pendingSleepCount == 1 }

        await clock.advance(by: 300)
        try await waitUntil { await client.requestCount == 2 }

        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()
        let latestState = try XCTUnwrap(await iterator.next())
        XCTAssertEqual(latestState.reviewCount, 2)
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not become true")
    }
}

private actor ManuallyAdvancingRefreshClock: RefreshClock {
    private var current: Date
    private var sleepers: [(deadline: Date, continuation: CheckedContinuation<Void, Error>)] = []

    init(now: Date) {
        current = now
    }

    var pendingSleepCount: Int { sleepers.count }

    func now() async -> Date { current }

    func sleep(for duration: Duration) async throws {
        let deadline = current.addingTimeInterval(duration.timeInterval)
        try await withCheckedThrowingContinuation { continuation in
            sleepers.append((deadline, continuation))
        }
    }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
        let due = sleepers.filter { $0.deadline <= current }
        sleepers.removeAll { $0.deadline <= current }
        for sleeper in due {
            sleeper.continuation.resume(returning: ())
        }
    }
}

private struct ConnectedVerificationAccount: AccountConnection {
    func inspect(selectedLogin: String?) async -> AccountConnectionResult {
        .connected(
            ResolvedAccount(
                login: "FranciscoMoretti",
                hostname: "github.com",
                scopes: ["read:org", "repo"],
                accessCoverage: AccessCoverage(isComplete: true),
                accessToken: GitHubAccessToken("test-token")
            )
        )
    }
}

private actor ReviewCountWorkloadClient: GitHubWorkloadClient {
    private var reviewCounts: [Int]
    private(set) var requestCount = 0

    init(reviewCounts: [Int]) {
        self.reviewCounts = reviewCounts
    }

    func reconcile(account: ResolvedAccount) async -> WorkloadReconciliationResult {
        requestCount += 1
        let count = reviewCounts.isEmpty ? 0 : reviewCounts.removeFirst()
        let pullRequests = (0..<count).map { index in
            PullRequestPresentation(
                id: "PR-\(index)",
                repositoryID: "REPO",
                repositoryNameWithOwner: "owner/repo",
                number: index + 1,
                title: "Review \(index + 1)",
                url: URL(string: "https://github.com/owner/repo/pull/\(index + 1)")!,
                isDraft: false,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                reviewers: []
            )
        }
        return .complete(
            WorkloadSnapshot(
                hostname: account.hostname,
                accountLogin: account.login,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                completeness: .complete,
                availableRepositories: [],
                needsYourReview: pullRequests,
                authoredPullRequests: []
            ),
            .empty
        )
    }
}
