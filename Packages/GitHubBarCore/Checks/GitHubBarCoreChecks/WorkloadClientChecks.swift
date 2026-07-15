import Foundation
import GitHubBarCore

enum WorkloadClientChecks {
    static func run() async -> [String] {
        var failures: [String] = []
        let transport = WorkloadFixtureTransport()
        let client = GraphQLGitHubWorkloadClient(transport: transport)
        let account = ResolvedAccount(
            login: "FranciscoMoretti",
            hostname: "github.com",
            scopes: ["read:org", "repo"],
            accessCoverage: AccessCoverage(isComplete: true),
            accessToken: GitHubAccessToken("fixture-token")
        )

        let result = await client.reconcile(account: account, repositoryScope: .all, previousSnapshot: nil)
        guard case let .complete(snapshot, _) = result else {
            return ["FAILED: Complete direct/team/authored workload reconciliation"]
        }

        check(snapshot.waitingForReview.map(\.id) == ["PR-1", "PR-2"], "Direct and team review requests deduplicate", failures: &failures)
        check(snapshot.authoredPullRequests.map(\.id) == ["PR-3"], "Authored pull requests are separate", failures: &failures)
        check(snapshot.authoredPullRequests.first?.isDraft == true, "Drafts remain in My PRs", failures: &failures)
        check(snapshot.waitingForReview.first?.reviewers.count == 4, "Review roster combines requests, submitted reviews, and later pages", failures: &failures)
        check(snapshot.availableRepositories.map(\.id) == ["REPO-1", "REPO-2"], "Accessible Repository catalog is independent of active PRs", failures: &failures)

        let selectedTransport = WorkloadFixtureTransport()
        let selectedClient = GraphQLGitHubWorkloadClient(transport: selectedTransport)
        _ = await selectedClient.reconcile(
            account: account,
            repositoryScope: .selected(["REPO-1"]),
            previousSnapshot: nil
        )
        let scopedQueries = await selectedTransport.searchQueries()
        check(
            !scopedQueries.isEmpty && scopedQueries.allSatisfy { $0.contains("repo:alaro-ai/app") },
            "Repository scope constrains every discovery search",
            failures: &failures
        )

        let rateLimitStart = Date()
        let rateLimitedClient = GraphQLGitHubWorkloadClient(transport: RateLimitedFixtureTransport())
        let rateLimitedResult = await rateLimitedClient.reconcile(
            account: account,
            repositoryScope: .all,
            previousSnapshot: nil
        )
        if case let .failed(.rateLimited, metadata) = rateLimitedResult {
            check(
                metadata.resetAt.map { $0 >= rateLimitStart.addingTimeInterval(59) } == true,
                "Retry-After metadata informs rate-limit recovery",
                failures: &failures
            )
        } else {
            failures.append("FAILED: HTTP rate limits retain retry metadata")
        }
        return failures
    }

    private static func check(_ condition: Bool, _ message: String, failures: inout [String]) {
        if !condition { failures.append("FAILED: \(message)") }
    }
}

private struct RateLimitedFixtureTransport: GitHubTransport {
    func execute(body: Data, accessToken: GitHubAccessToken) async throws -> GitHubTransportResponse {
        throw GitHubTransportError.http(statusCode: 429, retryAfter: 60, rateLimitResetAt: nil)
    }
}

private actor WorkloadFixtureTransport: GitHubTransport {
    private var recordedSearchQueries: [String] = []

    func searchQueries() -> [String] { recordedSearchQueries }

    func execute(body: Data, accessToken: GitHubAccessToken) async throws -> GitHubTransportResponse {
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let operationName = object?["operationName"] as? String
        let variables = object?["variables"] as? [String: Any]

        let response: String
        switch operationName {
        case "ViewerRepositories":
            response = #"{"data":{"viewer":{"repositories":{"nodes":[{"id":"REPO-1","nameWithOwner":"alaro-ai/app","isArchived":false},{"id":"REPO-2","nameWithOwner":"FranciscoMoretti/chat-js","isArchived":false}],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"rateLimit":{"cost":1,"remaining":5000,"resetAt":"2026-07-15T20:00:00Z"}}}"#
        case "ViewerOrganizations":
            response = #"{"data":{"viewer":{"organizations":{"nodes":[{"login":"alaro-ai"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"rateLimit":{"cost":1,"remaining":4999,"resetAt":"2026-07-15T20:00:00Z"}}}"#
        case "OrganizationTeams":
            response = #"{"data":{"organization":{"teams":{"nodes":[{"name":"devs","slug":"devs","avatarUrl":null,"organization":{"login":"alaro-ai"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"rateLimit":{"cost":1,"remaining":4998,"resetAt":"2026-07-15T20:00:00Z"}}}"#
        case "SearchPullRequests":
            let query = variables?["query"] as? String ?? ""
            recordedSearchQueries.append(query)
            if query.contains("user-review-requested:") {
                response = searchResponse(ids: ["PR-1"])
            } else if query.contains("team-review-requested:") {
                response = searchResponse(ids: ["PR-1", "PR-2"])
            } else {
                response = searchResponse(ids: ["PR-3"])
            }
        case "HydratePullRequests":
            response = Self.hydrationResponse.replacingOccurrences(
                of: #""hasNextPage":false,"endCursor":null"#,
                with: #""hasNextPage":true,"endCursor":"next""#
            )
        case "PullRequestRosterPage":
            response = #"{"data":{"node":{"reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"User","login":"dave","avatarUrl":null}}],"pageInfo":{"hasNextPage":false,"endCursor":null}},"reviews":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"rateLimit":{"cost":1,"remaining":4995,"resetAt":"2026-07-15T20:00:00Z"}}}"#
        default:
            throw FixtureError.unexpectedOperation
        }

        return GitHubTransportResponse(statusCode: 200, headers: [:], data: Data(response.utf8))
    }

    private func searchResponse(ids: [String]) -> String {
        let nodes = ids.map { #"{"id":"\#($0)"}"# }.joined(separator: ",")
        return #"{"data":{"search":{"nodes":[\#(nodes)],"pageInfo":{"hasNextPage":false,"endCursor":null}},"rateLimit":{"cost":1,"remaining":4997,"resetAt":"2026-07-15T20:00:00Z"}}}"#
    }

    private static let hydrationResponse = #"{"data":{"nodes":[{"id":"PR-1","number":1,"title":"Direct review","url":"https://github.com/alaro-ai/app/pull/1","isDraft":false,"state":"OPEN","updatedAt":"2026-07-15T12:00:00Z","author":{"login":"alice"},"repository":{"id":"REPO-1","nameWithOwner":"alaro-ai/app"},"reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"User","login":"FranciscoMoretti","avatarUrl":null}},{"requestedReviewer":{"__typename":"User","login":"alice","avatarUrl":null}}],"pageInfo":{"hasNextPage":false,"endCursor":null}},"reviews":{"nodes":[{"author":{"login":"bob","avatarUrl":null}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}},{"id":"PR-2","number":2,"title":"Team review","url":"https://github.com/alaro-ai/app/pull/2","isDraft":false,"state":"OPEN","updatedAt":"2026-07-15T13:00:00Z","author":{"login":"carol"},"repository":{"id":"REPO-1","nameWithOwner":"alaro-ai/app"},"reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"Team","name":"devs","slug":"devs","avatarUrl":null,"organization":{"login":"alaro-ai"}}}],"pageInfo":{"hasNextPage":false,"endCursor":null}},"reviews":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}},{"id":"PR-3","number":3,"title":"My draft","url":"https://github.com/alaro-ai/app/pull/3","isDraft":true,"state":"OPEN","updatedAt":"2026-07-15T14:00:00Z","author":{"login":"FranciscoMoretti"},"repository":{"id":"REPO-1","nameWithOwner":"alaro-ai/app"},"reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"User","login":"alice","avatarUrl":null}}],"pageInfo":{"hasNextPage":false,"endCursor":null}},"reviews":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}],"rateLimit":{"cost":1,"remaining":4996,"resetAt":"2026-07-15T20:00:00Z"}}}"#

    private enum FixtureError: Error {
        case unexpectedOperation
    }
}
