import Foundation
import GitHubBarCore

enum GitHubBarCoreChecks {
    static func run() async {
        var failures: [String] = []

        let engine = WorkloadEngine(initialState: .empty)
        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()

        guard let initialState = await iterator.next() else {
            fatalError("WorkloadEngine ended its state stream before publishing its initial state")
        }

        check(initialState == .empty, "Initial state is empty", failures: &failures)
        check(initialState.reviewCount == 0, "Initial Review count is zero", failures: &failures)
        check(ReviewCountBadge.text(for: 0) == nil, "Zero Review count hides its badge", failures: &failures)
        check(ReviewCountBadge.text(for: 4) == "4", "Single-digit Review count is shown", failures: &failures)
        check(ReviewCountBadge.text(for: 10) == "9+", "Double-digit Review count is capped visually", failures: &failures)
        check(
            initialState.reviewCountAccessibilityLabel == "No pull requests waiting for your review",
            "Zero Review count has an exact accessibility label",
            failures: &failures
        )

        await engine.send(.selectRepositoryScope(.selected(["openai/codex"])))
        guard let scopedState = await iterator.next() else {
            fatalError("WorkloadEngine ended its state stream before publishing a Repository scope change")
        }
        check(
            scopedState.repositoryScope == .selected(["openai/codex"]),
            "Repository scope changes publish",
            failures: &failures
        )

        await checkAccountSelection(failures: &failures)
        failures.append(contentsOf: await WorkloadClientChecks.run())
        failures.append(contentsOf: await SnapshotStoreChecks.run())

        if failures.isEmpty {
            print("GitHubBarCore checks passed")
        } else {
            fatalError(failures.joined(separator: "\n"))
        }
    }

    private static func check(_ condition: Bool, _ message: String, failures: inout [String]) {
        if !condition {
            failures.append("FAILED: \(message)")
        }
    }

    private static func checkAccountSelection(failures: inout [String]) async {
        let runner = AccountCheckCommandRunner()
        let connection = GitHubCLIAccountConnection(
            executableLocator: FixedExecutableLocator(url: URL(fileURLWithPath: "/opt/homebrew/bin/gh")),
            commandRunner: runner
        )

        let unselected = await connection.inspect(selectedLogin: nil)
        if case let .selectionRequired(candidates) = unselected {
            check(candidates.map(\.login) == ["FranciscoMoretti", "francisco-acme"], "Multiple accounts require an explicit selection", failures: &failures)
        } else {
            failures.append("FAILED: Multiple accounts require an explicit selection")
        }

        let selected = await connection.inspect(selectedLogin: "francisco-acme")
        if case let .connected(account) = selected {
            check(account.login == "francisco-acme", "Selected account is verified", failures: &failures)
            check(account.accessCoverage.isComplete, "Required Access coverage is detected", failures: &failures)
            check(!String(reflecting: selected).contains("secret-test-token"), "Account credentials are redacted", failures: &failures)
        } else {
            failures.append("FAILED: Selected account connects")
        }
    }
}

await GitHubBarCoreChecks.run()

private struct FixedExecutableLocator: GitHubCLIExecutableLocating {
    let url: URL?

    func locate() -> URL? { url }
}

private actor AccountCheckCommandRunner: CommandRunning {
    func run(executableURL: URL, arguments: [String], environment: [String: String]) async -> CommandResult {
        if arguments.starts(with: ["auth", "status"]) {
            return CommandResult(
                exitCode: 0,
                standardOutput: #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"FranciscoMoretti","tokenSource":"keyring","scopes":"gist, read:org, repo","gitProtocol":"https"},{"state":"success","active":false,"host":"github.com","login":"francisco-acme","tokenSource":"keyring","scopes":"read:org, repo","gitProtocol":"https"}]}}"#,
                standardError: ""
            )
        }
        if arguments.starts(with: ["auth", "token"]) {
            return CommandResult(exitCode: 0, standardOutput: "secret-test-token\n", standardError: "")
        }
        if arguments.starts(with: ["api", "user"]) {
            return CommandResult(exitCode: 0, standardOutput: "francisco-acme\n", standardError: "")
        }
        return CommandResult(exitCode: 1, standardOutput: "", standardError: "Unexpected command")
    }
}
