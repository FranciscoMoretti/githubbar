import Foundation
import GitHubBarCore

enum ReconciliationChecks {
    static func run() async -> [String] {
        var failures: [String] = []
        failures.append(contentsOf: await checkSingleFlight())
        failures.append(contentsOf: await checkPartialMerge())
        failures.append(contentsOf: await checkFailureRetention())
        failures.append(contentsOf: await checkAccountRace())
        failures.append(contentsOf: await checkRateLimitRetryBound())
        failures.append(contentsOf: await checkSchedulingTransitions())
        failures.append(contentsOf: await checkLaunchAtLoginMapping())
        failures.append(contentsOf: await checkPopoverOpenRefresh())
        failures.append(contentsOf: checkAdaptivePolicy())
        failures.append(contentsOf: await checkLargeWorkload())
        return failures
    }

    private static func checkSingleFlight() async -> [String] {
        let client = ScriptedWorkloadClient(
            results: [
                .complete(snapshot(ids: ["FIRST"]), .empty),
                .complete(snapshot(ids: ["SECOND"]), .empty),
            ],
            delay: .milliseconds(40)
        )
        let engine = makeEngine(client: client)

        async let launch: Void = engine.send(.launch)
        try? await Task.sleep(for: .milliseconds(5))
        async let manual: Void = engine.send(.manualRefresh)
        _ = await (launch, manual)

        var failures: [String] = []
        check(await client.maximumConcurrentRequests == 1, "Overlapping triggers remain single-flight", failures: &failures)
        check(await client.requestCount <= 2, "Overlapping triggers coalesce to at most one queued refresh", failures: &failures)
        return failures
    }

    private static func checkPartialMerge() async -> [String] {
        let initial = snapshot(ids: ["A", "B"])
        let partial = snapshot(ids: ["A"], titleSuffix: " updated", completeness: .partial)
        let client = ScriptedWorkloadClient(results: [
            .complete(initial, .empty),
            .partial(partial, ReconciliationMetadata(queryCost: 2, remainingPoints: 100, resetAt: nil, warnings: ["One shard failed"])),
        ])
        let engine = makeEngine(client: client)
        await engine.send(.launch)
        await engine.send(.manualRefresh)
        let state = await latestState(from: engine)

        var failures: [String] = []
        check(Set(state.authoredPullRequests.map(\.id)) == ["A", "B"], "Partial results do not delete unconfirmed Pull Requests", failures: &failures)
        check(state.authoredPullRequests.first(where: { $0.id == "A" })?.title == "A updated", "Partial results apply confirmed updates", failures: &failures)
        check(state.refreshHealth == .partial(message: "One shard failed"), "Partial results publish degraded health", failures: &failures)
        return failures
    }

    private static func checkFailureRetention() async -> [String] {
        let client = ScriptedWorkloadClient(results: [
            .complete(snapshot(ids: ["KEEP"]), .empty),
            .failed(.unavailable, .empty),
        ])
        let engine = makeEngine(client: client)
        await engine.send(.launch)
        await engine.send(.manualRefresh)
        let state = await latestState(from: engine)

        var failures: [String] = []
        check(state.authoredPullRequests.map(\.id) == ["KEEP"], "Total failure retains the last useful workload", failures: &failures)
        check(state.refreshHealth == .failed(message: "GitHub could not refresh the active workload."), "Total failure explains degraded freshness", failures: &failures)
        return failures
    }

    private static func checkRateLimitRetryBound() async -> [String] {
        let clock = ImmediateRefreshClock()
        let client = ScriptedWorkloadClient(results: [
            .failed(.rateLimited, ReconciliationMetadata(queryCost: 1, remainingPoints: 0, resetAt: Date(timeIntervalSince1970: 1_700_000_010), warnings: [])),
            .failed(.rateLimited, .empty),
            .complete(snapshot(ids: ["RECOVERED"]), .empty),
        ])
        let engine = makeEngine(client: client, clock: clock)
        await engine.send(.launch)
        for _ in 0..<20 where await client.requestCount < 3 {
            await Task.yield()
        }
        let state = await latestState(from: engine)

        var failures: [String] = []
        check(await client.requestCount == 3, "Rate limits retry within a bounded attempt budget", failures: &failures)
        check(state.authoredPullRequests.map(\.id) == ["RECOVERED"], "A bounded rate-limit retry can recover", failures: &failures)
        check(await clock.sleepCount == 2, "Rate-limit retry waits through the injected Clock", failures: &failures)
        return failures
    }

    private static func checkAccountRace() async -> [String] {
        let engine = WorkloadEngine(
            accountConnection: RacingAccountConnection(),
            workloadClient: AccountEchoWorkloadClient(),
            settingsStore: InMemorySettingsStore(
                settings: AppSettings(selectedLogin: "old-account", refreshCadence: .manual)
            )
        )
        async let launch: Void = engine.send(.launch)
        try? await Task.sleep(for: .milliseconds(5))
        await engine.send(.confirmAccount("new-account"))
        await launch
        let state = await latestState(from: engine)

        var failures: [String] = []
        if case let .connected(login, _) = state.accountConnection {
            check(login == "new-account", "A stale Account inspection cannot replace the newer selection", failures: &failures)
        } else {
            failures.append("FAILED: The newer Account remains connected after an inspection race")
        }
        check(state.authoredPullRequests.map(\.id) == ["new-account"], "A stale Account cannot publish its workload", failures: &failures)
        return failures
    }

    private static func checkLargeWorkload() async -> [String] {
        let ids = (0..<500).map { "PR-\($0)" }
        let client = ScriptedWorkloadClient(results: [.complete(snapshot(ids: ids), .empty)])
        let engine = makeEngine(client: client)
        let start = ContinuousClock.now
        await engine.send(.launch)
        let duration = start.duration(to: .now)
        let state = await latestState(from: engine)

        var failures: [String] = []
        check(state.authoredPullRequests.count == 500, "A 500 Pull Request fixture reconciles completely", failures: &failures)
        check(duration < .seconds(10), "A 500 Pull Request fixture reconciles in under 10 seconds", failures: &failures)
        return failures
    }

    private static func checkSchedulingTransitions() async -> [String] {
        let clock = RecordingSuspendingRefreshClock()
        let client = ScriptedWorkloadClient(results: [.complete(snapshot(ids: ["A"]), .empty)])
        let settings = InMemorySettingsStore(
            settings: AppSettings(selectedLogin: "FranciscoMoretti", refreshCadence: .fiveMinutes)
        )
        let engine = WorkloadEngine(
            accountConnection: ReconciliationAccountConnection(),
            workloadClient: client,
            settingsStore: settings,
            clock: clock
        )
        await engine.send(.launch)
        await waitForSleepCount(1, clock: clock)
        await engine.send(.setRefreshCadence(.oneMinute))
        await waitForSleepCount(2, clock: clock)
        await engine.send(.setRefreshCadence(.manual))

        let durations = await clock.durations
        var failures: [String] = []
        check(durations.first == .seconds(300), "The default fixed schedule starts at five minutes", failures: &failures)
        check(durations.dropFirst().first == .seconds(60), "Changing cadence replaces the pending timer", failures: &failures)
        return failures
    }

    private static func checkPopoverOpenRefresh() async -> [String] {
        let clock = ImmediateRefreshClock()
        let client = ScriptedWorkloadClient(results: [
            .complete(snapshot(ids: ["A"]), .empty),
            .complete(snapshot(ids: ["B"]), .empty),
        ])
        let engine = makeEngine(client: client, clock: clock)
        await engine.send(.launch)
        await engine.send(.setPopoverOpen(true))
        for _ in 0..<20 {
            if await client.requestCount >= 2 { break }
            await Task.yield()
        }
        await engine.send(.setPopoverOpen(false))

        var failures: [String] = []
        check(await client.requestCount == 2, "A sustained Popover open refreshes through the same lane", failures: &failures)
        return failures
    }

    private static func checkLaunchAtLoginMapping() async -> [String] {
        let controller = RecordingLaunchAtLoginController()
        let settings = InMemorySettingsStore(
            settings: AppSettings(selectedLogin: "FranciscoMoretti", refreshCadence: .manual)
        )
        let engine = WorkloadEngine(
            accountConnection: ReconciliationAccountConnection(),
            workloadClient: ScriptedWorkloadClient(results: [.complete(snapshot(ids: []), .empty)]),
            settingsStore: settings,
            launchAtLoginController: controller
        )
        await engine.send(.launch)
        await engine.send(.setLaunchAtLogin(true))
        var state = await latestState(from: engine)

        var failures: [String] = []
        check(state.launchAtLoginRequested, "Launch at login opt-in publishes", failures: &failures)
        check(state.launchAtLoginStatus == .enabled, "Launch at login registration state maps to presentation", failures: &failures)
        check(await settings.load().launchAtLogin, "Launch at login opt-in persists through SettingsStore", failures: &failures)

        await controller.failNextChange()
        await engine.send(.setLaunchAtLogin(false))
        state = await latestState(from: engine)
        if case .failed = state.launchAtLoginStatus {
            check(true, "Launch at login failures publish actionably", failures: &failures)
        } else {
            failures.append("FAILED: Launch at login failures publish actionably")
        }
        check(await settings.load().launchAtLogin, "Failed launch registration does not persist a false state", failures: &failures)
        return failures
    }

    private static func checkAdaptivePolicy() -> [String] {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cases: [(TimeInterval?, AdaptiveRefreshReason)] = [
            (nil, .longIdle),
            (300, .recentInteraction),
            (301, .warm),
            (3_601, .idle),
            (14_400, .longIdle),
        ]
        var failures: [String] = []
        for (age, expected) in cases {
            let openedAt = age.map { now.addingTimeInterval(-$0) }
            check(
                AdaptiveRefreshPolicy.decision(now: now, lastPopoverOpenAt: openedAt).reason == expected,
                "Adaptive schedule honors the \(expected.rawValue) boundary",
                failures: &failures
            )
        }
        check(
            AdaptiveRefreshPolicy.decision(now: now, lastPopoverOpenAt: now, isConstrained: true).reason == .constrained,
            "Constrained state takes adaptive scheduling precedence",
            failures: &failures
        )
        return failures
    }

    private static func waitForSleepCount(_ count: Int, clock: RecordingSuspendingRefreshClock) async {
        for _ in 0..<50 {
            if await clock.durations.count >= count { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func makeEngine(
        client: ScriptedWorkloadClient,
        clock: any RefreshClock = SystemRefreshClock()
    ) -> WorkloadEngine {
        WorkloadEngine(
            accountConnection: ReconciliationAccountConnection(),
            workloadClient: client,
            settingsStore: InMemorySettingsStore(settings: AppSettings(selectedLogin: "FranciscoMoretti", refreshCadence: .manual)),
            clock: clock
        )
    }

    private static func latestState(from engine: WorkloadEngine) async -> AppPresentationState {
        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()
        return await iterator.next() ?? .empty
    }

    private static func snapshot(
        ids: [String],
        titleSuffix: String = "",
        completeness: WorkloadSnapshot.Completeness = .complete
    ) -> WorkloadSnapshot {
        WorkloadSnapshot(
            hostname: "github.com",
            accountLogin: "FranciscoMoretti",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completeness: completeness,
            repositoryScope: .all,
            availableRepositories: [RepositoryChoice(id: "REPO", nameWithOwner: "owner/repo")],
            waitingForReview: [],
            authoredPullRequests: ids.enumerated().map { index, id in
                PullRequestPresentation(
                    id: id,
                    repositoryID: "REPO",
                    repositoryNameWithOwner: "owner/repo",
                    number: index + 1,
                    title: id + titleSuffix,
                    url: URL(string: "https://github.com/owner/repo/pull/\(index + 1)")!,
                    isDraft: false,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(index)),
                    reviewers: []
                )
            }
        )
    }

    private static func check(_ condition: Bool, _ message: String, failures: inout [String]) {
        if !condition { failures.append("FAILED: \(message)") }
    }
}

private struct ReconciliationAccountConnection: AccountConnection {
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

private actor ScriptedWorkloadClient: GitHubWorkloadClient {
    private var results: [WorkloadReconciliationResult]
    private let delay: Duration
    private(set) var requestCount = 0
    private(set) var maximumConcurrentRequests = 0
    private var concurrentRequests = 0

    init(results: [WorkloadReconciliationResult], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    func reconcile(
        account: ResolvedAccount,
        repositoryScope: RepositoryScope,
        previousSnapshot: WorkloadSnapshot?
    ) async -> WorkloadReconciliationResult {
        requestCount += 1
        concurrentRequests += 1
        maximumConcurrentRequests = max(maximumConcurrentRequests, concurrentRequests)
        if delay > .zero { try? await Task.sleep(for: delay) }
        concurrentRequests -= 1
        if results.isEmpty { return .failed(.unavailable, .empty) }
        return results.removeFirst()
    }
}

private actor ImmediateRefreshClock: RefreshClock {
    private(set) var sleepCount = 0

    func now() async -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    func sleep(for duration: Duration) async throws {
        sleepCount += 1
    }
}

private actor RecordingSuspendingRefreshClock: RefreshClock {
    private(set) var durations: [Duration] = []

    func now() async -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
        try await Task.sleep(for: .seconds(3_600))
    }
}

private struct RacingAccountConnection: AccountConnection {
    func inspect(selectedLogin: String?) async -> AccountConnectionResult {
        let login = selectedLogin ?? "old-account"
        try? await Task.sleep(for: login == "old-account" ? .milliseconds(60) : .milliseconds(5))
        return .connected(
            ResolvedAccount(
                login: login,
                hostname: "github.com",
                scopes: ["read:org", "repo"],
                accessCoverage: AccessCoverage(isComplete: true),
                accessToken: GitHubAccessToken("test-token")
            )
        )
    }
}

private struct AccountEchoWorkloadClient: GitHubWorkloadClient {
    func reconcile(
        account: ResolvedAccount,
        repositoryScope: RepositoryScope,
        previousSnapshot: WorkloadSnapshot?
    ) async -> WorkloadReconciliationResult {
        let pullRequest = PullRequestPresentation(
            id: account.login,
            repositoryID: "REPO",
            repositoryNameWithOwner: "owner/repo",
            number: 1,
            title: account.login,
            url: URL(string: "https://github.com/owner/repo/pull/1")!,
            isDraft: false,
            updatedAt: Date(),
            reviewers: []
        )
        return .complete(
            WorkloadSnapshot(
                hostname: account.hostname,
                accountLogin: account.login,
                capturedAt: Date(),
                completeness: .complete,
                repositoryScope: repositoryScope,
                availableRepositories: [],
                waitingForReview: [],
                authoredPullRequests: [pullRequest]
            ),
            .empty
        )
    }
}

private actor RecordingLaunchAtLoginController: LaunchAtLoginControlling {
    private var enabled = false
    private var shouldFail = false

    func status() async -> LaunchAtLoginStatus {
        enabled ? .enabled : .disabled
    }

    func setEnabled(_ isEnabled: Bool) async -> LaunchAtLoginStatus {
        if shouldFail {
            shouldFail = false
            return .failed(message: "Open System Settings and allow GitHubBar in Login Items.")
        }
        enabled = isEnabled
        return isEnabled ? .enabled : .disabled
    }

    func failNextChange() {
        shouldFail = true
    }
}
