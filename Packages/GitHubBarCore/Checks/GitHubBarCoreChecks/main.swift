import Foundation
import GitHubBarCore

@main
enum GitHubBarCoreChecks {
    static func main() async {
        var failures: [String] = []

        let engine = WorkloadEngine(initialState: .empty)
        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()

        guard let initialState = await iterator.next() else {
            fatalError("WorkloadEngine ended its state stream before publishing its initial state")
        }

        check(initialState == .empty, "Initial state is empty", failures: &failures)
        check(initialState.reviewCount == 0, "Initial Review count is zero", failures: &failures)
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
}
