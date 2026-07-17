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

        let result = await client.reconcile(account: account)
        guard case let .complete(snapshot, _) = result else {
            return ["FAILED: Complete direct/team/authored workload reconciliation"]
        }

        check(snapshot.needsYourReview.map(\.id) == ["PR-1", "PR-2"], "Direct and team review requests deduplicate", failures: &failures)
        check(snapshot.authoredPullRequests.map(\.id) == ["PR-3"], "Authored pull requests are separate", failures: &failures)
        check(
            snapshot.authoredPullRequests.first?.isDraft == true,
            "Drafts remain in the Authored pull-request workload",
            failures: &failures
        )
        check(
            snapshot.authoredPullRequests.first?.reviewDecision == .reviewRequired,
            "Aggregate Review decision hydrates",
            failures: &failures
        )
        check(
            snapshot.authoredPullRequests.first?.requestedReviewers?.map(\.displayName) == ["alice", "dave"],
            "Outstanding Review requests remain separate from the full Reviewer roster",
            failures: &failures
        )
        check(snapshot.needsYourReview.first?.reviewers.count == 4, "Review roster combines requests, submitted reviews, and later pages", failures: &failures)
        check(snapshot.availableRepositories.map(\.id) == ["REPO-1", "REPO-2"], "Accessible Repository catalog is independent of active PRs", failures: &failures)
        let accountWideQueries = await transport.searchQueries()
        check(
            !accountWideQueries.isEmpty && accountWideQueries.allSatisfy { !$0.contains("repo:") },
            "Reconciliation discovers the account-wide workload without Repository scope qualifiers",
            failures: &failures
        )

        let largeRosterResult = await GraphQLGitHubWorkloadClient(
            transport: WorkloadFixtureTransport(usesLargeRoster: true)
        ).reconcile(account: account)
        if case let .complete(largeRosterSnapshot, _) = largeRosterResult {
            check(
                largeRosterSnapshot.needsYourReview.first?.reviewers.count == 101,
                "Review rosters paginate beyond 100 entries without truncation",
                failures: &failures
            )
        } else {
            failures.append("FAILED: Review rosters above 100 entries reconcile")
        }

        let rateLimitStart = Date()
        let rateLimitedClient = GraphQLGitHubWorkloadClient(transport: RateLimitedFixtureTransport())
        let rateLimitedResult = await rateLimitedClient.reconcile(account: account)
        if case let .failed(.rateLimited, metadata) = rateLimitedResult {
            check(
                metadata.resetAt.map { $0 >= rateLimitStart.addingTimeInterval(59) } == true,
                "Retry-After metadata informs rate-limit recovery",
                failures: &failures
            )
        } else {
            failures.append("FAILED: HTTP rate limits retain retry metadata")
        }

        let organizationAuthorizationResult = await GraphQLGitHubWorkloadClient(
            transport: OrganizationAuthorizationFixtureTransport()
        ).reconcile(account: account)
        if case .failed(.organizationAuthorizationRequired, _) = organizationAuthorizationResult {
            // Expected: organization authorization is an access-coverage problem, not rate limiting.
        } else {
            failures.append("FAILED: Organization SSO authorization is diagnosed separately from rate limiting")
        }

        let partialPageResult = await GraphQLGitHubWorkloadClient(
            transport: PartialPageFixtureTransport()
        ).reconcile(account: account)
        if case let .partial(partialSnapshot, metadata) = partialPageResult {
            check(
                partialSnapshot.authoredPullRequests.map(\.id) == ["PR-3"],
                "A later failed search page keeps confirmed Pull Requests",
                failures: &failures
            )
            check(
                metadata.warnings.contains("pull-request search page incomplete"),
                "A later failed search page marks reconciliation partial",
                failures: &failures
            )
        } else {
            failures.append("FAILED: A later failed search page produces a partial reconciliation")
        }

        let scaleTransport = TargetScaleFixtureTransport(pullRequestCount: 500)
        let scaleClient = GraphQLGitHubWorkloadClient(transport: scaleTransport)
        let scaleStart = ContinuousClock.now
        let scaleResult = await scaleClient.reconcile(account: account)
        let scaleDuration = scaleStart.duration(to: .now)
        let scaleMetrics = await scaleTransport.metrics()
        if case let .complete(scaleSnapshot, _) = scaleResult {
            check(scaleSnapshot.authoredPullRequests.count == 500, "Production reconciliation hydrates 500 Pull Requests", failures: &failures)
            check(scaleDuration < .seconds(10), "Production reconciliation completes 500 Pull Requests in under 10 seconds", failures: &failures)
            check(scaleMetrics.searchPages == 6, "Production reconciliation paginates a 500 Pull Request search", failures: &failures)
            check(scaleMetrics.maximumHydrations > 1, "Production hydration runs concurrently", failures: &failures)
            check(scaleMetrics.maximumHydrations <= 4, "Production hydration concurrency remains bounded", failures: &failures)
        } else {
            failures.append("FAILED: Production reconciliation completes at the 500 Pull Request target")
        }

        let partialRateTransport = TargetScaleFixtureTransport(
            pullRequestCount: 40,
            rateLimitsFirstHydration: true
        )
        let partialRateResult = await GraphQLGitHubWorkloadClient(
            transport: partialRateTransport
        ).reconcile(account: account)
        if case let .partial(partialRateSnapshot, metadata) = partialRateResult {
            check(!partialRateSnapshot.authoredPullRequests.isEmpty, "Confirmed hydration batches survive a partial rate limit", failures: &failures)
            check(metadata.rateLimitEncountered, "A partial rate limit requests bounded backoff", failures: &failures)
        } else {
            failures.append("FAILED: A partial hydration rate limit retains confirmed batches")
        }
        return failures
    }

    private static func check(_ condition: Bool, _ message: String, failures: inout [String]) {
        if !condition { failures.append("FAILED: \(message)") }
    }
}

private actor PartialPageFixtureTransport: GitHubTransport {
    private let base = WorkloadFixtureTransport()

    func execute(body: Data, accessToken: GitHubAccessToken) async throws -> GitHubTransportResponse {
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let operationName = object?["operationName"] as? String
        let variables = object?["variables"] as? [String: Any]
        let query = variables?["query"] as? String ?? ""
        let cursor = variables?["cursor"]

        if operationName == "SearchPullRequests", query.contains("author:") {
            if cursor is NSNull || cursor == nil {
                let response = #"{"data":{"search":{"nodes":[{"id":"PR-3"}],"pageInfo":{"hasNextPage":true,"endCursor":"next"}},"rateLimit":{"cost":1,"remaining":4997,"resetAt":"2026-07-15T20:00:00Z"}}}"#
                return GitHubTransportResponse(statusCode: 200, headers: [:], data: Data(response.utf8))
            }
            throw PartialFixtureError.laterPageFailed
        }
        return try await base.execute(body: body, accessToken: accessToken)
    }

    private enum PartialFixtureError: Error {
        case laterPageFailed
    }
}

private actor TargetScaleFixtureTransport: GitHubTransport {
    private let pullRequestCount: Int
    private let rateLimitsFirstHydration: Bool
    private var currentHydrations = 0
    private var maximumHydrations = 0
    private var searchPages = 0
    private var didRateLimitHydration = false

    init(pullRequestCount: Int, rateLimitsFirstHydration: Bool = false) {
        self.pullRequestCount = pullRequestCount
        self.rateLimitsFirstHydration = rateLimitsFirstHydration
    }

    func metrics() -> (searchPages: Int, maximumHydrations: Int) {
        (searchPages, maximumHydrations)
    }

    func execute(body: Data, accessToken: GitHubAccessToken) async throws -> GitHubTransportResponse {
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let operationName = object?["operationName"] as? String
        let variables = object?["variables"] as? [String: Any]
        let data: Data

        switch operationName {
        case "ViewerRepositories":
            data = responseData([
                "viewer": ["repositories": [
                    "nodes": [["id": "REPO-1", "nameWithOwner": "owner/repo", "isArchived": false]],
                    "pageInfo": pageInfo(hasNextPage: false, endCursor: nil),
                ]],
                "rateLimit": rateLimit(),
            ])
        case "ViewerOrganizations":
            data = responseData([
                "viewer": ["organizations": [
                    "nodes": [],
                    "pageInfo": pageInfo(hasNextPage: false, endCursor: nil),
                ]],
                "rateLimit": rateLimit(),
            ])
        case "SearchPullRequests":
            searchPages += 1
            let query = variables?["query"] as? String ?? ""
            guard query.contains("author:") else {
                data = searchResponse(ids: [], nextCursor: nil)
                break
            }
            let page = Int(variables?["cursor"] as? String ?? "0") ?? 0
            let lowerBound = page * 100
            let upperBound = min(pullRequestCount, lowerBound + 100)
            let ids = lowerBound..<upperBound
            let nextCursor = upperBound < pullRequestCount ? String(page + 1) : nil
            data = searchResponse(ids: ids.map { "PR-\($0)" }, nextCursor: nextCursor)
        case "HydratePullRequests":
            if rateLimitsFirstHydration, !didRateLimitHydration {
                didRateLimitHydration = true
                throw GitHubTransportError.http(
                    statusCode: 429,
                    retryAfter: 5,
                    rateLimitResetAt: nil,
                    remainingRequests: 0,
                    organizationAuthorizationRequired: false
                )
            }
            currentHydrations += 1
            maximumHydrations = max(maximumHydrations, currentHydrations)
            try? await Task.sleep(for: .milliseconds(5))
            let ids = variables?["ids"] as? [String] ?? []
            let nodes = ids.map(hydratedNode(id:))
            currentHydrations -= 1
            data = responseData(["nodes": nodes, "rateLimit": rateLimit()])
        default:
            throw ScaleFixtureError.unexpectedOperation
        }

        return GitHubTransportResponse(statusCode: 200, headers: [:], data: data)
    }

    private func searchResponse(ids: [String], nextCursor: String?) -> Data {
        responseData([
            "search": [
                "nodes": ids.map { ["id": $0] },
                "pageInfo": pageInfo(hasNextPage: nextCursor != nil, endCursor: nextCursor),
            ],
            "rateLimit": rateLimit(),
        ])
    }

    private func hydratedNode(id: String) -> [String: Any] {
        let number = Int(id.replacingOccurrences(of: "PR-", with: "")) ?? 0
        return [
            "id": id,
            "number": number,
            "title": "Pull Request \(number)",
            "url": "https://github.com/owner/repo/pull/\(number)",
            "isDraft": false,
            "state": "OPEN",
            "updatedAt": "2026-07-15T12:00:00Z",
            "author": ["login": "FranciscoMoretti"],
            "repository": ["id": "REPO-1", "nameWithOwner": "owner/repo"],
            "reviewRequests": ["nodes": [], "pageInfo": pageInfo(hasNextPage: false, endCursor: nil)],
            "reviews": ["nodes": [], "pageInfo": pageInfo(hasNextPage: false, endCursor: nil)],
        ]
    }

    private func responseData(_ data: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["data": data])
    }

    private func pageInfo(hasNextPage: Bool, endCursor: String?) -> [String: Any] {
        ["hasNextPage": hasNextPage, "endCursor": endCursor ?? NSNull()]
    }

    private func rateLimit() -> [String: Any] {
        ["cost": 1, "remaining": 4_000, "resetAt": "2026-07-15T20:00:00Z"]
    }

    private enum ScaleFixtureError: Error {
        case unexpectedOperation
    }
}

private struct OrganizationAuthorizationFixtureTransport: GitHubTransport {
    func execute(body: Data, accessToken: GitHubAccessToken) async throws -> GitHubTransportResponse {
        throw GitHubTransportError.http(
            statusCode: 403,
            retryAfter: nil,
            rateLimitResetAt: nil,
            remainingRequests: 4_998,
            organizationAuthorizationRequired: true
        )
    }
}

private struct RateLimitedFixtureTransport: GitHubTransport {
    func execute(body: Data, accessToken: GitHubAccessToken) async throws -> GitHubTransportResponse {
        throw GitHubTransportError.http(
            statusCode: 429,
            retryAfter: 60,
            rateLimitResetAt: nil,
            remainingRequests: 0,
            organizationAuthorizationRequired: false
        )
    }
}

private actor WorkloadFixtureTransport: GitHubTransport {
    private var recordedSearchQueries: [String] = []
    private let usesLargeRoster: Bool

    init(usesLargeRoster: Bool = false) {
        self.usesLargeRoster = usesLargeRoster
    }

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
            if usesLargeRoster {
                response = Self.largeRosterHydrationResponse
            } else {
                response = Self.hydrationResponse
                    .replacingOccurrences(
                        of: #""isDraft":true,"state":"OPEN""#,
                        with: #""isDraft":true,"reviewDecision":"REVIEW_REQUIRED","state":"OPEN""#
                    )
                    .replacingOccurrences(
                        of: #""hasNextPage":false,"endCursor":null"#,
                        with: #""hasNextPage":true,"endCursor":"next""#
                    )
            }
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

    private static var largeRosterHydrationResponse: String {
        let reviewers = (["FranciscoMoretti"] + (1..<100).map { "reviewer-\($0)" })
            .map { #"{"requestedReviewer":{"__typename":"User","login":"\#($0)","avatarUrl":null}}"# }
            .joined(separator: ",")
        return #"{"data":{"nodes":[{"id":"PR-1","number":1,"title":"Large roster","url":"https://github.com/alaro-ai/app/pull/1","isDraft":false,"state":"OPEN","updatedAt":"2026-07-15T12:00:00Z","author":{"login":"alice"},"repository":{"id":"REPO-1","nameWithOwner":"alaro-ai/app"},"reviewRequests":{"nodes":[\#(reviewers)],"pageInfo":{"hasNextPage":true,"endCursor":"next"}},"reviews":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}],"rateLimit":{"cost":1,"remaining":4996,"resetAt":"2026-07-15T20:00:00Z"}}}"#
    }

    private enum FixtureError: Error {
        case unexpectedOperation
    }
}
