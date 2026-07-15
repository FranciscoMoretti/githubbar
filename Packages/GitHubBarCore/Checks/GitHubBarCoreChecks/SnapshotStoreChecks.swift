import Foundation
import GitHubBarCore

enum SnapshotStoreChecks {
    static func run() async -> [String] {
        var failures: [String] = []
        let snapshot = fixtureSnapshot()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubbar-snapshot-check-\(UUID().uuidString)", isDirectory: true)
        let store = FileSnapshotStore(directoryURL: directory)

        do {
            try await store.save(snapshot)
            let loaded = try await store.load(hostname: "github.com", accountLogin: "FranciscoMoretti")
            check(loaded == snapshot, "Snapshot atomically round-trips", failures: &failures)
            let otherAccount = try await store.load(hostname: "github.com", accountLogin: "someone-else")
            check(otherAccount == nil, "Snapshot is isolated by monitored account", failures: &failures)

            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            if let snapshotFile = files.first {
                let permissions = try FileManager.default.attributesOfItem(atPath: snapshotFile.path)[.posixPermissions] as? NSNumber
                check(permissions?.intValue == 0o600, "Snapshot file is owner-only", failures: &failures)
                try Data("not-json".utf8).write(to: snapshotFile, options: .atomic)
                let corrupt = try? await store.load(hostname: "github.com", accountLogin: "FranciscoMoretti")
                check(corrupt == nil, "Corrupt Snapshot is rejected", failures: &failures)
            } else {
                failures.append("FAILED: Snapshot file is created")
            }
        } catch {
            failures.append("FAILED: Snapshot store round trip")
        }

        let memoryStore = InMemorySnapshotStore(snapshot: snapshot)
        let engine = WorkloadEngine(
            accountConnection: DelayedAccountConnection(),
            snapshotStore: memoryStore,
            settingsStore: InMemorySettingsStore(
                settings: AppSettings(selectedLogin: "FranciscoMoretti")
            )
        )
        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        let cacheStart = ContinuousClock.now
        let launch = Task { await engine.send(.launch) }
        if let cachedState = await iterator.next() {
            check(cachedState.authoredPullRequests.map(\.id) == ["SNAPSHOT-PR"], "Cached presentation publishes before account inspection", failures: &failures)
            check(cacheStart.duration(to: .now) < .milliseconds(250), "Cached presentation publishes within 250 ms", failures: &failures)
        } else {
            failures.append("FAILED: Cached presentation publishes before account inspection")
        }
        await launch.value

        try? FileManager.default.removeItem(at: directory)
        return failures
    }

    private static func fixtureSnapshot() -> WorkloadSnapshot {
        WorkloadSnapshot(
            hostname: "github.com",
            accountLogin: "FranciscoMoretti",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completeness: .complete,
            repositoryScope: .all,
            availableRepositories: [RepositoryChoice(id: "REPO", nameWithOwner: "owner/repo")],
            waitingForReview: [],
            authoredPullRequests: [
                PullRequestPresentation(
                    id: "SNAPSHOT-PR",
                    repositoryID: "REPO",
                    repositoryNameWithOwner: "owner/repo",
                    number: 1,
                    title: "Cached pull request",
                    url: URL(string: "https://github.com/owner/repo/pull/1")!,
                    isDraft: false,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    reviewers: []
                ),
            ]
        )
    }

    private static func check(_ condition: Bool, _ message: String, failures: inout [String]) {
        if !condition { failures.append("FAILED: \(message)") }
    }
}

private struct DelayedAccountConnection: AccountConnection {
    func inspect(selectedLogin: String?) async -> AccountConnectionResult {
        try? await Task.sleep(for: .milliseconds(50))
        return .authenticationRequired
    }
}
