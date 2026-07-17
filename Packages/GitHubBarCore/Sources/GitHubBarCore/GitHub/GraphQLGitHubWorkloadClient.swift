import Foundation

public struct GraphQLGitHubWorkloadClient: GitHubWorkloadClient {
    private let transport: any GitHubTransport
    private let hydrationBatchSize: Int
    private let hydrationConcurrency: Int

    public init(
        transport: any GitHubTransport = URLSessionGitHubTransport(),
        hydrationBatchSize: Int = 20,
        hydrationConcurrency: Int = 4
    ) {
        self.transport = transport
        self.hydrationBatchSize = max(1, hydrationBatchSize)
        self.hydrationConcurrency = max(1, hydrationConcurrency)
    }

    public func reconcile(account: ResolvedAccount) async -> WorkloadReconciliationResult {
        var metadata = MetadataAccumulator()

        let repositoryCatalog: [RepositoryChoice]
        do {
            let output = try await discoverRepositories(account: account)
            repositoryCatalog = output.value
            metadata.merge(output.metadata)
        } catch {
            metadata.record(error: error)
            return .failed(failure(for: error, fallback: .discovery), metadata.presentation)
        }
        let teams: [TeamReference]
        do {
            let output = try await discoverTeams(account: account)
            teams = output.value
            metadata.merge(output.metadata)
        } catch {
            metadata.record(error: error)
            return .failed(failure(for: error, fallback: .discovery), metadata.presentation)
        }

        let directIDs: [String]
        do {
            let output = try await searchPullRequestIDs(
                query: "is:pr is:open user-review-requested:\(account.login) sort:updated-asc",
                account: account
            )
            directIDs = output.value
            metadata.merge(output.metadata)
        } catch {
            metadata.record(error: error)
            return .failed(failure(for: error, fallback: .discovery), metadata.presentation)
        }

        var teamIDs: [String] = []
        for team in teams {
            do {
                let output = try await searchPullRequestIDs(
                    query: "is:pr is:open team-review-requested:\(team.searchQualifier) sort:updated-asc",
                    account: account
                )
                teamIDs.append(contentsOf: output.value)
                metadata.merge(output.metadata)
            } catch {
                metadata.record(error: error, warning: "team-review discovery incomplete")
            }
        }

        let authoredIDs: [String]
        do {
            let output = try await searchPullRequestIDs(
                query: "is:pr is:open author:\(account.login) sort:updated-desc",
                account: account
            )
            authoredIDs = output.value
            metadata.merge(output.metadata)
        } catch {
            metadata.record(error: error)
            return .failed(failure(for: error, fallback: .discovery), metadata.presentation)
        }

        let reviewDiscoveryIDs = Set(directIDs + teamIDs)
        let authoredDiscoveryIDs = Set(authoredIDs)
        let allIDs = Array(reviewDiscoveryIDs.union(authoredDiscoveryIDs)).sorted()

        let hydrationOutput = await hydrateAll(ids: allIDs, account: account)
        let hydratedRecords = hydrationOutput.value
        metadata.merge(hydrationOutput.metadata)

        if !allIDs.isEmpty, hydratedRecords.isEmpty {
            return .failed(metadata.blockingFailure ?? .hydration, metadata.presentation)
        }

        let monitoredReviewerKeys = Set(
            ["user:\(account.login.lowercased())"] + teams.map(\.reviewerKey)
        )

        let recordsByID = Dictionary(uniqueKeysWithValues: hydratedRecords.map { ($0.id, $0) })
        let needsYourReview = reviewDiscoveryIDs.compactMap { id -> PullRequestPresentation? in
            guard let record = recordsByID[id],
                  !record.isDraft,
                  !record.requestedReviewerKeys.isDisjoint(with: monitoredReviewerKeys) else {
                return nil
            }
            return record.presentation
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.id < rhs.id
        }

        let authoredPullRequests = authoredDiscoveryIDs.compactMap { id -> PullRequestPresentation? in
            guard let record = recordsByID[id],
                  record.authorLogin.caseInsensitiveCompare(account.login) == .orderedSame else {
                return nil
            }
            return record.presentation
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id < rhs.id
        }

        let completeness: WorkloadSnapshot.Completeness = metadata.warnings.isEmpty ? .complete : .partial
        let snapshot = WorkloadSnapshot(
            hostname: account.hostname,
            accountLogin: account.login,
            capturedAt: Date(),
            completeness: completeness,
            availableRepositories: repositoryCatalog,
            needsYourReview: needsYourReview,
            authoredPullRequests: authoredPullRequests
        )

        if completeness == .complete {
            return .complete(snapshot, metadata.presentation)
        }
        return .partial(snapshot, metadata.presentation)
    }

    private func discoverRepositories(account: ResolvedAccount) async throws -> OperationOutput<[RepositoryChoice]> {
        var metadata = MetadataAccumulator()
        var repositories: [RepositoryChoice] = []
        var cursor: String?

        repeat {
            do {
                let page: Executed<ViewerRepositoriesData> = try await execute(
                    operationName: "ViewerRepositories",
                    query: Self.viewerRepositoriesQuery,
                    variables: CursorVariables(cursor: cursor),
                    account: account
                )
                repositories.append(contentsOf: page.data.viewer.repositories.nodes.map {
                    RepositoryChoice(id: $0.id, nameWithOwner: $0.nameWithOwner)
                })
                metadata.record(
                    rateLimit: page.data.rateLimit,
                    hasErrors: page.hasErrors,
                    warning: "repository catalog incomplete"
                )
                cursor = page.data.viewer.repositories.pageInfo.hasNextPage
                    ? page.data.viewer.repositories.pageInfo.endCursor
                    : nil
            } catch {
                if repositories.isEmpty || isAccessBlocking(error) { throw error }
                metadata.record(error: error, warning: "repository catalog page incomplete")
                cursor = nil
            }
        } while cursor != nil

        let uniqueRepositories = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
            .values
            .sorted { $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending }
        return OperationOutput(value: uniqueRepositories, metadata: metadata)
    }

    private func discoverTeams(account: ResolvedAccount) async throws -> OperationOutput<[TeamReference]> {
        var metadata = MetadataAccumulator()
        var organizations: [String] = []
        var cursor: String?

        repeat {
            do {
                let page: Executed<ViewerOrganizationsData> = try await execute(
                    operationName: "ViewerOrganizations",
                    query: Self.viewerOrganizationsQuery,
                    variables: CursorVariables(cursor: cursor),
                    account: account
                )
                organizations.append(contentsOf: page.data.viewer.organizations.nodes.map(\.login))
                metadata.record(rateLimit: page.data.rateLimit, hasErrors: page.hasErrors, warning: "organization discovery incomplete")
                cursor = page.data.viewer.organizations.pageInfo.hasNextPage
                    ? page.data.viewer.organizations.pageInfo.endCursor
                    : nil
            } catch {
                if organizations.isEmpty || isAccessBlocking(error) { throw error }
                metadata.record(error: error, warning: "organization discovery page incomplete")
                cursor = nil
            }
        } while cursor != nil

        var teams: [TeamReference] = []
        for organization in organizations {
            var teamCursor: String?
            repeat {
                do {
                    let page: Executed<OrganizationTeamsData> = try await execute(
                        operationName: "OrganizationTeams",
                        query: Self.organizationTeamsQuery,
                        variables: TeamVariables(
                            organization: organization,
                            userLogin: account.login,
                            cursor: teamCursor
                        ),
                        account: account
                    )
                    guard let organizationData = page.data.organization else {
                        metadata.warnings.append("organization team discovery incomplete")
                        break
                    }
                    teams.append(contentsOf: organizationData.teams.nodes.map {
                        TeamReference(
                            organizationLogin: $0.organization.login,
                            slug: $0.slug,
                            name: $0.name,
                            avatarURL: $0.avatarURL.flatMap(URL.init(string:))
                        )
                    })
                    metadata.record(rateLimit: page.data.rateLimit, hasErrors: page.hasErrors, warning: "organization team discovery incomplete")
                    teamCursor = organizationData.teams.pageInfo.hasNextPage
                        ? organizationData.teams.pageInfo.endCursor
                        : nil
                } catch {
                    if isAccessBlocking(error) { throw error }
                    metadata.record(error: error, warning: "organization team discovery incomplete")
                    teamCursor = nil
                }
            } while teamCursor != nil
        }

        let uniqueTeams = Dictionary(uniqueKeysWithValues: teams.map { ($0.reviewerKey, $0) })
            .values
            .sorted { $0.searchQualifier < $1.searchQualifier }
        return OperationOutput(value: uniqueTeams, metadata: metadata)
    }

    private func searchPullRequestIDs(
        query searchQuery: String,
        account: ResolvedAccount
    ) async throws -> OperationOutput<[String]> {
        var metadata = MetadataAccumulator()
        var ids: [String] = []
        var cursor: String?

        repeat {
            do {
                let page: Executed<SearchPullRequestsData> = try await execute(
                    operationName: "SearchPullRequests",
                    query: Self.searchPullRequestsQuery,
                    variables: SearchVariables(query: searchQuery, cursor: cursor),
                    account: account
                )
                ids.append(contentsOf: page.data.search.nodes.compactMap(\.id))
                metadata.record(rateLimit: page.data.rateLimit, hasErrors: page.hasErrors, warning: "pull-request search incomplete")
                cursor = page.data.search.pageInfo.hasNextPage ? page.data.search.pageInfo.endCursor : nil
            } catch {
                if ids.isEmpty || isAccessBlocking(error) { throw error }
                metadata.record(error: error, warning: "pull-request search page incomplete")
                cursor = nil
            }
        } while cursor != nil

        return OperationOutput(value: Array(Set(ids)), metadata: metadata)
    }

    private func hydrate(ids: [String], account: ResolvedAccount) async throws -> OperationOutput<[HydratedRecord]> {
        let page: Executed<HydratePullRequestsData> = try await execute(
            operationName: "HydratePullRequests",
            query: Self.hydratePullRequestsQuery,
            variables: HydrateVariables(ids: ids),
            account: account
        )
        var metadata = MetadataAccumulator()
        metadata.record(rateLimit: page.data.rateLimit, hasErrors: page.hasErrors, warning: "pull-request hydration incomplete")
        var records = page.data.nodes.compactMap { $0.flatMap(HydratedRecord.init) }

        for index in records.indices {
            while records[index].reviewRequestsPageInfo.hasNextPage || records[index].reviewsPageInfo.hasNextPage {
                let includeReviewRequests = records[index].reviewRequestsPageInfo.hasNextPage
                let includeReviews = records[index].reviewsPageInfo.hasNextPage
                do {
                    let rosterPage: Executed<PullRequestRosterPageData> = try await execute(
                        operationName: "PullRequestRosterPage",
                        query: Self.pullRequestRosterPageQuery,
                        variables: RosterPageVariables(
                            id: records[index].id,
                            reviewRequestsCursor: records[index].reviewRequestsPageInfo.endCursor,
                            reviewsCursor: records[index].reviewsPageInfo.endCursor,
                            includeReviewRequests: includeReviewRequests,
                            includeReviews: includeReviews
                        ),
                        account: account
                    )
                    metadata.record(
                        rateLimit: rosterPage.data.rateLimit,
                        hasErrors: rosterPage.hasErrors,
                        warning: "review roster pagination incomplete"
                    )
                    guard let pullRequest = rosterPage.data.node else {
                        metadata.warnings.append("review roster pagination incomplete")
                        break
                    }
                    if let reviewRequests = pullRequest.reviewRequests {
                        records[index].requestedReviewers.append(contentsOf: reviewRequests.nodes.compactMap(\.requestedReviewer))
                        records[index].reviewRequestsPageInfo = reviewRequests.pageInfo
                    }
                    if let reviews = pullRequest.reviews {
                        records[index].reviewAuthors.append(contentsOf: reviews.nodes.compactMap(\.author))
                        records[index].reviewsPageInfo = reviews.pageInfo
                    }
                } catch {
                    metadata.warnings.append("review roster pagination incomplete")
                    break
                }
            }
        }

        return OperationOutput(
            value: records,
            metadata: metadata
        )
    }

    private func hydrateAll(
        ids: [String],
        account: ResolvedAccount
    ) async -> OperationOutput<[HydratedRecord]> {
        let batches = ids.chunked(into: hydrationBatchSize)
        guard !batches.isEmpty else { return OperationOutput(value: [], metadata: MetadataAccumulator()) }

        return await withTaskGroup(of: HydrationBatchOutcome.self) { group in
            var nextBatchIndex = 0
            var recordsByBatch: [Int: [HydratedRecord]] = [:]
            var metadataByBatch: [Int: MetadataAccumulator] = [:]

            func submitBatch(at index: Int) {
                let batch = batches[index]
                group.addTask {
                    do {
                        return .success(index: index, output: try await hydrate(ids: batch, account: account))
                    } catch {
                        return .failure(index: index, error: CapturedOperationError(error))
                    }
                }
            }

            while nextBatchIndex < min(hydrationConcurrency, batches.count) {
                submitBatch(at: nextBatchIndex)
                nextBatchIndex += 1
            }

            while let outcome = await group.next() {
                switch outcome {
                case let .success(index, output):
                    recordsByBatch[index] = output.value
                    metadataByBatch[index] = output.metadata
                case let .failure(index, error):
                    var failedMetadata = MetadataAccumulator()
                    failedMetadata.record(error: error, warning: "pull-request hydration incomplete")
                    metadataByBatch[index] = failedMetadata
                }

                if nextBatchIndex < batches.count {
                    submitBatch(at: nextBatchIndex)
                    nextBatchIndex += 1
                }
            }

            var metadata = MetadataAccumulator()
            for index in batches.indices {
                if let batchMetadata = metadataByBatch[index] { metadata.merge(batchMetadata) }
            }
            return OperationOutput(
                value: batches.indices.flatMap { recordsByBatch[$0] ?? [] },
                metadata: metadata
            )
        }
    }

    private func execute<Variables: Encodable & Sendable, Response: Decodable & Sendable>(
        operationName: String,
        query: String,
        variables: Variables,
        account: ResolvedAccount
    ) async throws -> Executed<Response> {
        let body = try JSONEncoder().encode(
            GraphQLRequest(operationName: operationName, query: query, variables: variables)
        )
        let response = try await transport.execute(body: body, accessToken: account.accessToken)
        let envelope = try JSONDecoder().decode(GraphQLEnvelope<Response>.self, from: response.data)
        guard let data = envelope.data else {
            throw GraphQLClientError.missingData
        }
        return Executed(data: data, hasErrors: !(envelope.errors ?? []).isEmpty)
    }

    private func isAccessBlocking(_ error: Error) -> Bool {
        let transportError: GitHubTransportError?
        if let direct = error as? GitHubTransportError {
            transportError = direct
        } else if let captured = error as? CapturedOperationError {
            transportError = captured.transportError
        } else {
            transportError = nil
        }
        guard let transportError else { return false }
        return failure(for: transportError, fallback: .discovery) == .rateLimited
            || failure(for: transportError, fallback: .discovery) == .organizationAuthorizationRequired
    }

    private func failure(for error: Error?, fallback: WorkloadFailure) -> WorkloadFailure {
        guard let error else { return fallback }
        if case let GitHubTransportError.http(
            statusCode,
            retryAfter,
            rateLimitResetAt,
            remainingRequests,
            organizationAuthorizationRequired
        ) = error {
            if organizationAuthorizationRequired {
                return .organizationAuthorizationRequired
            }
            if statusCode == 429
                || (statusCode == 403 && (remainingRequests == 0 || retryAfter != nil || rateLimitResetAt != nil)) {
                return .rateLimited
            }
        }
        return fallback
    }
}

private extension GraphQLGitHubWorkloadClient {
    static let viewerRepositoriesQuery = #"""
    query ViewerRepositories($cursor: String) {
      viewer {
        repositories(
          first: 100
          after: $cursor
          affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]
          ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]
          isArchived: false
          orderBy: { field: UPDATED_AT, direction: DESC }
        ) {
          nodes { id nameWithOwner isArchived }
          pageInfo { hasNextPage endCursor }
        }
      }
      rateLimit { cost remaining resetAt }
    }
    """#

    static let viewerOrganizationsQuery = #"""
    query ViewerOrganizations($cursor: String) {
      viewer {
        organizations(first: 100, after: $cursor) {
          nodes { login }
          pageInfo { hasNextPage endCursor }
        }
      }
      rateLimit { cost remaining resetAt }
    }
    """#

    static let organizationTeamsQuery = #"""
    query OrganizationTeams($organization: String!, $userLogin: String!, $cursor: String) {
      organization(login: $organization) {
        teams(first: 100, after: $cursor, userLogins: [$userLogin]) {
          nodes {
            name
            slug
            avatarUrl
            organization { login }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
      rateLimit { cost remaining resetAt }
    }
    """#

    static let searchPullRequestsQuery = #"""
    query SearchPullRequests($query: String!, $cursor: String) {
      search(query: $query, type: ISSUE, first: 100, after: $cursor) {
        nodes { ... on PullRequest { id } }
        pageInfo { hasNextPage endCursor }
      }
      rateLimit { cost remaining resetAt }
    }
    """#

    static let hydratePullRequestsQuery = #"""
    query HydratePullRequests($ids: [ID!]!) {
      nodes(ids: $ids) {
        ... on PullRequest {
          id
          number
          title
          url
          isDraft
          reviewDecision
          state
          updatedAt
          author { login }
          repository { id nameWithOwner }
          reviewRequests(first: 100) {
            nodes {
              requestedReviewer {
                __typename
                ... on User { login avatarUrl }
                ... on Bot { login avatarUrl }
                ... on Mannequin { login avatarUrl }
                ... on Team { name slug avatarUrl organization { login } }
                ... on EnterpriseTeam { name slug combinedSlug }
              }
            }
            pageInfo { hasNextPage endCursor }
          }
          reviews(first: 100) {
            nodes { author { login avatarUrl } }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
      rateLimit { cost remaining resetAt }
    }
    """#

    static let pullRequestRosterPageQuery = #"""
    query PullRequestRosterPage(
      $id: ID!
      $reviewRequestsCursor: String
      $reviewsCursor: String
      $includeReviewRequests: Boolean!
      $includeReviews: Boolean!
    ) {
      node(id: $id) {
        ... on PullRequest {
          reviewRequests(first: 100, after: $reviewRequestsCursor) @include(if: $includeReviewRequests) {
            nodes {
              requestedReviewer {
                __typename
                ... on User { login avatarUrl }
                ... on Bot { login avatarUrl }
                ... on Mannequin { login avatarUrl }
                ... on Team { name slug avatarUrl organization { login } }
                ... on EnterpriseTeam { name slug combinedSlug }
              }
            }
            pageInfo { hasNextPage endCursor }
          }
          reviews(first: 100, after: $reviewsCursor) @include(if: $includeReviews) {
            nodes { author { login avatarUrl } }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
      rateLimit { cost remaining resetAt }
    }
    """#
}

private struct GraphQLRequest<Variables: Encodable>: Encodable {
    let operationName: String
    let query: String
    let variables: Variables
}

private struct GraphQLEnvelope<Response: Decodable>: Decodable {
    let data: Response?
    let errors: [GraphQLErrorDTO]?
}

private struct GraphQLErrorDTO: Decodable {
    let type: String?
}

private struct Executed<Response: Sendable>: Sendable {
    let data: Response
    let hasErrors: Bool
}

private enum GraphQLClientError: Error {
    case missingData
}

private struct OperationOutput<Value: Sendable>: Sendable {
    let value: Value
    let metadata: MetadataAccumulator
}

private struct MetadataAccumulator: Sendable {
    var queryCost = 0
    var remainingPoints: Int?
    var resetAt: Date?
    var warnings: [String] = []
    var blockingFailure: WorkloadFailure?

    mutating func record(error: Error, warning: String? = nil) {
        if let warning { warnings.append(warning) }
        let transportError: GitHubTransportError?
        if let direct = error as? GitHubTransportError {
            transportError = direct
        } else if let captured = error as? CapturedOperationError {
            transportError = captured.transportError
        } else {
            transportError = nil
        }
        guard let transportError,
              case let GitHubTransportError.http(_, retryAfter, rateLimitResetAt, _, _) = transportError else { return }
        if case let .http(_, _, _, _, organizationAuthorizationRequired) = transportError,
           organizationAuthorizationRequired {
            blockingFailure = .organizationAuthorizationRequired
        } else if case let .http(statusCode, retryAfter, resetAt, remainingRequests, _) = transportError,
                  statusCode == 429
                    || (statusCode == 403 && (remainingRequests == 0 || retryAfter != nil || resetAt != nil)) {
            blockingFailure = .rateLimited
        }
        let retryAt = retryAfter.map { Date().addingTimeInterval($0) }
        if let candidate = rateLimitResetAt ?? retryAt {
            resetAt = max(resetAt ?? .distantPast, candidate)
        }
    }

    mutating func record(rateLimit: RateLimitDTO, hasErrors: Bool, warning: String) {
        queryCost += rateLimit.cost
        remainingPoints = rateLimit.remaining
        resetAt = parseGitHubDate(rateLimit.resetAt)
        if hasErrors { warnings.append(warning) }
    }

    mutating func merge(_ other: MetadataAccumulator) {
        queryCost += other.queryCost
        if let remaining = other.remainingPoints { remainingPoints = remaining }
        if let reset = other.resetAt { resetAt = reset }
        warnings.append(contentsOf: other.warnings)
        if blockingFailure != .organizationAuthorizationRequired {
            blockingFailure = other.blockingFailure ?? blockingFailure
        }
    }

    var presentation: ReconciliationMetadata {
        ReconciliationMetadata(
            queryCost: queryCost,
            remainingPoints: remainingPoints,
            resetAt: resetAt,
            warnings: warnings,
            rateLimitEncountered: blockingFailure == .rateLimited
        )
    }
}

private struct CapturedOperationError: Error, Sendable {
    let transportError: GitHubTransportError?

    init(_ error: Error) {
        transportError = error as? GitHubTransportError
    }
}

private enum HydrationBatchOutcome: Sendable {
    case success(index: Int, output: OperationOutput<[HydratedRecord]>)
    case failure(index: Int, error: CapturedOperationError)
}

private struct CursorVariables: Encodable, Sendable {
    let cursor: String?
}

private struct TeamVariables: Encodable, Sendable {
    let organization: String
    let userLogin: String
    let cursor: String?
}

private struct SearchVariables: Encodable, Sendable {
    let query: String
    let cursor: String?
}

private struct HydrateVariables: Encodable, Sendable {
    let ids: [String]
}

private struct RosterPageVariables: Encodable, Sendable {
    let id: String
    let reviewRequestsCursor: String?
    let reviewsCursor: String?
    let includeReviewRequests: Bool
    let includeReviews: Bool
}

private struct ViewerOrganizationsData: Decodable, Sendable {
    let viewer: ViewerDTO
    let rateLimit: RateLimitDTO
}

private struct ViewerRepositoriesData: Decodable, Sendable {
    let viewer: ViewerRepositoriesDTO
    let rateLimit: RateLimitDTO
}

private struct ViewerRepositoriesDTO: Decodable, Sendable {
    let repositories: RepositoryConnectionDTO
}

private struct RepositoryConnectionDTO: Decodable, Sendable {
    let nodes: [RepositoryCatalogDTO]
    let pageInfo: PageInfoDTO
}

private struct RepositoryCatalogDTO: Decodable, Sendable {
    let id: String
    let nameWithOwner: String
    let isArchived: Bool
}

private struct ViewerDTO: Decodable, Sendable {
    let organizations: OrganizationConnectionDTO
}

private struct OrganizationConnectionDTO: Decodable, Sendable {
    let nodes: [OrganizationDTO]
    let pageInfo: PageInfoDTO
}

private struct OrganizationDTO: Decodable, Sendable {
    let login: String
}

private struct OrganizationTeamsData: Decodable, Sendable {
    let organization: OrganizationWithTeamsDTO?
    let rateLimit: RateLimitDTO
}

private struct OrganizationWithTeamsDTO: Decodable, Sendable {
    let teams: TeamConnectionDTO
}

private struct TeamConnectionDTO: Decodable, Sendable {
    let nodes: [TeamDTO]
    let pageInfo: PageInfoDTO
}

private struct TeamDTO: Decodable, Sendable {
    let name: String
    let slug: String
    let avatarURL: String?
    let organization: OrganizationDTO

    private enum CodingKeys: String, CodingKey {
        case name, slug, organization
        case avatarURL = "avatarUrl"
    }
}

private struct SearchPullRequestsData: Decodable, Sendable {
    let search: SearchConnectionDTO
    let rateLimit: RateLimitDTO
}

private struct SearchConnectionDTO: Decodable, Sendable {
    let nodes: [SearchNodeDTO]
    let pageInfo: PageInfoDTO
}

private struct SearchNodeDTO: Decodable, Sendable {
    let id: String?
}

private struct HydratePullRequestsData: Decodable, Sendable {
    let nodes: [PullRequestDTO?]
    let rateLimit: RateLimitDTO
}

private struct PullRequestRosterPageData: Decodable, Sendable {
    let node: PullRequestRosterPageDTO?
    let rateLimit: RateLimitDTO
}

private struct PullRequestRosterPageDTO: Decodable, Sendable {
    let reviewRequests: ReviewRequestConnectionDTO?
    let reviews: ReviewConnectionDTO?
}

private struct PullRequestDTO: Decodable, Sendable {
    let id: String
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let reviewDecision: String?
    let state: String
    let updatedAt: String
    let author: ActorDTO?
    let repository: RepositoryDTO
    let reviewRequests: ReviewRequestConnectionDTO
    let reviews: ReviewConnectionDTO
}

private struct RepositoryDTO: Decodable, Sendable {
    let id: String
    let nameWithOwner: String
}

private struct ReviewRequestConnectionDTO: Decodable, Sendable {
    let nodes: [ReviewRequestDTO]
    let pageInfo: PageInfoDTO
}

private struct ReviewRequestDTO: Decodable, Sendable {
    let requestedReviewer: RequestedReviewerDTO?
}

private struct RequestedReviewerDTO: Decodable, Sendable {
    let typeName: String
    let login: String?
    let avatarURL: String?
    let name: String?
    let slug: String?
    let combinedSlug: String?
    let organization: OrganizationDTO?

    private enum CodingKeys: String, CodingKey {
        case typeName = "__typename"
        case login, name, slug, combinedSlug, organization
        case avatarURL = "avatarUrl"
    }
}

private struct ReviewConnectionDTO: Decodable, Sendable {
    let nodes: [ReviewDTO]
    let pageInfo: PageInfoDTO
}

private struct ReviewDTO: Decodable, Sendable {
    let author: ActorDTO?
}

private struct ActorDTO: Decodable, Sendable {
    let login: String
    let avatarURL: String?

    private enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatarUrl"
    }
}

private struct PageInfoDTO: Decodable, Sendable {
    let hasNextPage: Bool
    let endCursor: String?
}

private struct RateLimitDTO: Decodable, Sendable {
    let cost: Int
    let remaining: Int
    let resetAt: String
}

private struct TeamReference: Sendable {
    let organizationLogin: String
    let slug: String
    let name: String
    let avatarURL: URL?

    var searchQualifier: String { "\(organizationLogin)/\(slug)" }
    var reviewerKey: String { "team:\(searchQualifier.lowercased())" }
}

private struct HydratedRecord: Sendable {
    let id: String
    let repositoryID: String
    let repositoryNameWithOwner: String
    let authorLogin: String
    let isDraft: Bool
    let reviewDecision: PullRequestReviewDecision?
    let number: Int
    let title: String
    let url: URL
    let updatedAt: Date
    var requestedReviewers: [RequestedReviewerDTO]
    var reviewAuthors: [ActorDTO]
    var reviewRequestsPageInfo: PageInfoDTO
    var reviewsPageInfo: PageInfoDTO

    init?(_ dto: PullRequestDTO) {
        guard dto.state == "OPEN",
              let url = URL(string: dto.url),
              let updatedAt = parseGitHubDate(dto.updatedAt),
              let author = dto.author else {
            return nil
        }

        id = dto.id
        repositoryID = dto.repository.id
        repositoryNameWithOwner = dto.repository.nameWithOwner
        authorLogin = author.login
        isDraft = dto.isDraft
        reviewDecision = dto.reviewDecision.flatMap(PullRequestReviewDecision.init(rawValue:))
        number = dto.number
        title = dto.title
        self.url = url
        self.updatedAt = updatedAt
        requestedReviewers = dto.reviewRequests.nodes.compactMap(\.requestedReviewer)
        reviewAuthors = dto.reviews.nodes.compactMap(\.author)
        reviewRequestsPageInfo = dto.reviewRequests.pageInfo
        reviewsPageInfo = dto.reviews.pageInfo
    }

    var requestedReviewerKeys: Set<String> {
        Set(requestedReviewers.compactMap(\.reviewerKey))
    }

    var presentation: PullRequestPresentation {
        let requestedReviewerPresentations = requestedReviewers.compactMap(\.presentation)
        var reviewersByID: [String: ReviewerPresentation] = [:]
        var reviewerOrder: [String] = []
        for reviewer in requestedReviewerPresentations {
            if reviewersByID[reviewer.id] == nil { reviewerOrder.append(reviewer.id) }
            reviewersByID[reviewer.id] = reviewer
        }
        for reviewer in reviewAuthors.map(\.reviewerPresentation) {
            if reviewersByID[reviewer.id] == nil { reviewerOrder.append(reviewer.id) }
            reviewersByID[reviewer.id] = reviewer
        }

        return PullRequestPresentation(
            id: id,
            repositoryID: repositoryID,
            repositoryNameWithOwner: repositoryNameWithOwner,
            number: number,
            title: title,
            url: url,
            isDraft: isDraft,
            reviewDecision: reviewDecision,
            updatedAt: updatedAt,
            requestedReviewers: requestedReviewerPresentations,
            reviewers: reviewerOrder.compactMap { reviewersByID[$0] }
        )
    }
}

private extension RequestedReviewerDTO {
    var reviewerKey: String? {
        switch typeName {
        case "Team":
            guard let organizationLogin = organization?.login, let slug else { return nil }
            return "team:\(organizationLogin.lowercased())/\(slug.lowercased())"
        case "EnterpriseTeam":
            guard let combinedSlug else { return nil }
            return "team:\(combinedSlug.lowercased())"
        default:
            guard let login else { return nil }
            return "user:\(login.lowercased())"
        }
    }

    var presentation: ReviewerPresentation? {
        guard let reviewerKey else { return nil }
        if typeName == "Team" || typeName == "EnterpriseTeam" {
            let displayName = organization.map { organization in
                "\(organization.login)/\(slug ?? name ?? "team")"
            } ?? combinedSlug ?? name ?? "Team"
            return ReviewerPresentation(
                id: reviewerKey,
                displayName: displayName,
                avatarURL: avatarURL.flatMap(URL.init(string:)),
                kind: .team
            )
        }
        guard let login else { return nil }
        return ReviewerPresentation(
            id: reviewerKey,
            displayName: login,
            avatarURL: avatarURL.flatMap(URL.init(string:)),
            kind: .person
        )
    }
}

private extension ActorDTO {
    var reviewerPresentation: ReviewerPresentation {
        ReviewerPresentation(
            id: "user:\(login.lowercased())",
            displayName: login,
            avatarURL: avatarURL.flatMap(URL.init(string:)),
            kind: .person
        )
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

private func parseGitHubDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
