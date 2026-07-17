import Foundation
import GitHubBarCore

enum RepositoryScopeChecks {
    static func run() async -> [String] {
        var failures: [String] = []
        failures.append(contentsOf: await checkImmediateProjection())
        let workloadClient = RacingWorkloadClient()
        let settingsStore = InMemorySettingsStore(
            settings: AppSettings(selectedLogin: "FranciscoMoretti")
        )
        let engine = WorkloadEngine(
            accountConnection: ScopeAccountConnection(),
            workloadClient: workloadClient,
            settingsStore: settingsStore
        )
        let stream = await engine.states()
        let recorder = ScopeStateRecorder()
        let recording = Task {
            for await state in stream {
                await recorder.append(state)
            }
        }
        let starts = await workloadClient.starts()
        var startIterator = starts.makeAsyncIterator()

        let launch = Task { await engine.send(.launch) }
        _ = await startIterator.next()
        await engine.send(.selectRepositoryScope(.selected(["REPO-1"])))
        await launch.value
        try? await Task.sleep(for: .milliseconds(20))
        recording.cancel()

        let finalState = await recorder.values.last
        check(finalState?.repositoryScope == .selected(["REPO-1"]), "Latest Repository scope remains selected", failures: &failures)
        check(finalState?.authoredPullRequests.map(\.id) == ["IN-SCOPE"], "A completed reconciliation is projected through the latest Repository scope", failures: &failures)
        check(await workloadClient.requestCount == 1, "A Repository scope change does not reconcile", failures: &failures)
        check(await settingsStore.load().repositoryScope == .selected(["REPO-1"]), "Repository scope persists", failures: &failures)
        return failures
    }

    private static func checkImmediateProjection() async -> [String] {
        let snapshot = WorkloadSnapshot(
            hostname: "github.com",
            accountLogin: "FranciscoMoretti",
            capturedAt: Date(),
            completeness: .complete,
            availableRepositories: [
                RepositoryChoice(id: "REPO-1", nameWithOwner: "owner/one"),
                RepositoryChoice(id: "REPO-2", nameWithOwner: "owner/two"),
            ],
            needsYourReview: [pullRequest(id: "REVIEW-1", repositoryID: "REPO-1")],
            authoredPullRequests: [
                pullRequest(id: "AUTHORED-1", repositoryID: "REPO-1"),
                pullRequest(id: "AUTHORED-2", repositoryID: "REPO-2"),
            ]
        )
        let engine = WorkloadEngine(
            accountConnection: DelayedScopeAccountConnection(),
            snapshotStore: InMemorySnapshotStore(snapshot: snapshot),
            settingsStore: InMemorySettingsStore(settings: AppSettings(selectedLogin: "FranciscoMoretti"))
        )
        let states = await engine.states()
        let recorder = ScopeStateRecorder()
        let recording = Task {
            for await state in states { await recorder.append(state) }
        }
        let launch = Task { await engine.send(.launch) }

        for _ in 0..<50 {
            if await recorder.values.contains(where: { $0.authoredPullRequests.count == 2 }) { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        await engine.send(.selectRepositoryScope(.selected(["REPO-1"])))
        for _ in 0..<50 {
            if await recorder.values.contains(where: { $0.repositoryScope == .selected(["REPO-1"]) }) { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        let projectedState = await recorder.values.last(where: { $0.repositoryScope == .selected(["REPO-1"]) })
        await engine.send(.selectRepositoryScope(.all))
        for _ in 0..<50 {
            if await recorder.values.contains(where: {
                $0.repositoryScope == .all && $0.authoredPullRequests.count == 2
            }) { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        let allRepositoriesState = await recorder.values.last(where: {
            $0.repositoryScope == .all && $0.authoredPullRequests.count == 2
        })
        recording.cancel()
        await launch.value

        var failures: [String] = []
        check(
            projectedState?.authoredPullRequests.map(\.repositoryID) == ["REPO-1"],
            "A Repository scope change immediately removes out-of-scope My PRs",
            failures: &failures
        )
        check(
            projectedState?.reviewCount == 1,
            "A Repository scope change immediately constrains the review count",
            failures: &failures
        )
        check(
            projectedState?.isRefreshing == false,
            "A Repository scope change does not enter a refreshing state",
            failures: &failures
        )
        check(
            allRepositoriesState?.authoredPullRequests.map(\.repositoryID) == ["REPO-1", "REPO-2"],
            "Returning to all repositories restores the preserved account workload",
            failures: &failures
        )
        return failures
    }

    private static func pullRequest(id: String, repositoryID: String) -> PullRequestPresentation {
        PullRequestPresentation(
            id: id,
            repositoryID: repositoryID,
            repositoryNameWithOwner: "owner/\(repositoryID)",
            number: 1,
            title: id,
            url: URL(string: "https://github.com/owner/repo/pull/1")!,
            isDraft: false,
            updatedAt: Date(),
            reviewers: []
        )
    }

    private static func check(_ condition: Bool, _ message: String, failures: inout [String]) {
        if !condition { failures.append("FAILED: \(message)") }
    }
}

private struct DelayedScopeAccountConnection: AccountConnection {
    func inspect(selectedLogin: String?) async -> AccountConnectionResult {
        try? await Task.sleep(for: .milliseconds(100))
        return .connectionRequired
    }
}

private struct ScopeAccountConnection: AccountConnection {
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

private actor RacingWorkloadClient: GitHubWorkloadClient {
    private let startedStream: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private(set) var requestCount = 0

    init() {
        (startedStream, startedContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func starts() -> AsyncStream<Void> { startedStream }

    func reconcile(account: ResolvedAccount) async -> WorkloadReconciliationResult {
        requestCount += 1
        startedContinuation.yield(())
        try? await Task.sleep(for: .milliseconds(80))
        return .complete(snapshot(), .empty)
    }

    private func snapshot() -> WorkloadSnapshot {
        WorkloadSnapshot(
            hostname: "github.com",
            accountLogin: "FranciscoMoretti",
            capturedAt: Date(),
            completeness: .complete,
            availableRepositories: [
                RepositoryChoice(id: "REPO-1", nameWithOwner: "alaro-ai/alaro"),
                RepositoryChoice(id: "REPO-2", nameWithOwner: "alaro-ai/other"),
            ],
            needsYourReview: [],
            authoredPullRequests: [
                PullRequestPresentation(
                    id: "IN-SCOPE",
                    repositoryID: "REPO-1",
                    repositoryNameWithOwner: "alaro-ai/alaro",
                    number: 1,
                    title: "In scope",
                    url: URL(string: "https://github.com/alaro-ai/alaro/pull/1")!,
                    isDraft: false,
                    updatedAt: Date(),
                    reviewers: []
                ),
                PullRequestPresentation(
                    id: "OUT-OF-SCOPE",
                    repositoryID: "REPO-2",
                    repositoryNameWithOwner: "alaro-ai/other",
                    number: 2,
                    title: "Out of scope",
                    url: URL(string: "https://github.com/alaro-ai/other/pull/2")!,
                    isDraft: false,
                    updatedAt: Date(),
                    reviewers: []
                ),
            ]
        )
    }
}

private actor ScopeStateRecorder {
    private(set) var values: [AppPresentationState] = []
    func append(_ state: AppPresentationState) { values.append(state) }
}
