import Foundation
import GitHubBarCore

enum PullRequestSectionChecks {
    static func run() -> [String] {
        var failures: [String] = []
        let reviewer = ReviewerPresentation(
            id: "user:reviewer",
            displayName: "reviewer",
            avatarURL: nil,
            kind: .person
        )

        check(
            pullRequest(isDraft: true, decision: .approved, requestedReviewers: [reviewer]).authoredSection == .drafts,
            "Draft classification takes precedence over review state",
            failures: &failures
        )
        check(
            pullRequest(decision: .changesRequested, requestedReviewers: [reviewer]).authoredSection == .returnedToYou,
            "Changes requested classifies as Returned to you",
            failures: &failures
        )
        check(
            pullRequest(decision: .approved).authoredSection == .approved,
            "Approved review decision classifies as Approved",
            failures: &failures
        )
        check(
            pullRequest(decision: .reviewRequired, requestedReviewers: [reviewer]).authoredSection == .waitingForReviewers,
            "Outstanding review requests classify as Waiting for reviewers",
            failures: &failures
        )
        check(
            pullRequest(decision: .reviewRequired).authoredSection == .needsReviewers,
            "Review-required PRs without outstanding requests classify as Needs reviewers",
            failures: &failures
        )
        check(
            pullRequest().authoredSection == .needsReviewers,
            "Unprotected PRs without outstanding requests classify as Needs reviewers",
            failures: &failures
        )
        checkLegacySnapshotFallback(reviewer: reviewer, failures: &failures)

        return failures
    }

    private static func checkLegacySnapshotFallback(
        reviewer: ReviewerPresentation,
        failures: inout [String]
    ) {
        let original = pullRequest(requestedReviewers: [reviewer])
        guard let encoded = try? JSONEncoder().encode(original),
              var object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            failures.append("FAILED: Legacy Pull Request fixture encodes")
            return
        }
        object.removeValue(forKey: "requestedReviewers")
        object.removeValue(forKey: "reviewDecision")
        guard let legacyData = try? JSONSerialization.data(withJSONObject: object),
              let decoded = try? JSONDecoder().decode(PullRequestPresentation.self, from: legacyData) else {
            failures.append("FAILED: Legacy Pull Request snapshot decodes")
            return
        }
        check(
            decoded.requestedReviewers == nil && decoded.authoredSection == nil,
            "Legacy snapshots preserve unknown Outstanding review-request state",
            failures: &failures
        )
    }

    private static func pullRequest(
        isDraft: Bool = false,
        decision: PullRequestReviewDecision? = nil,
        requestedReviewers: [ReviewerPresentation] = []
    ) -> PullRequestPresentation {
        PullRequestPresentation(
            id: "PR-1",
            repositoryID: "REPO-1",
            repositoryNameWithOwner: "example/repo",
            number: 1,
            title: "Example",
            url: URL(string: "https://github.com/example/repo/pull/1")!,
            isDraft: isDraft,
            reviewDecision: decision,
            updatedAt: Date(timeIntervalSince1970: 0),
            requestedReviewers: requestedReviewers,
            reviewers: requestedReviewers
        )
    }

    private static func check(_ condition: Bool, _ message: String, failures: inout [String]) {
        if !condition { failures.append("FAILED: \(message)") }
    }
}
