import Foundation

public struct WorkloadSnapshot: Codable, Equatable, Sendable {
    public enum Completeness: String, Codable, Equatable, Sendable {
        case complete
        case partial
    }

    public let schemaVersion: Int
    public let hostname: String
    public let accountLogin: String
    public let capturedAt: Date
    public let completeness: Completeness
    public let repositoryScope: RepositoryScope
    public let availableRepositories: [RepositoryChoice]
    public let waitingForReview: [PullRequestPresentation]
    public let authoredPullRequests: [PullRequestPresentation]

    public init(
        schemaVersion: Int = 1,
        hostname: String,
        accountLogin: String,
        capturedAt: Date,
        completeness: Completeness,
        repositoryScope: RepositoryScope,
        availableRepositories: [RepositoryChoice],
        waitingForReview: [PullRequestPresentation],
        authoredPullRequests: [PullRequestPresentation]
    ) {
        self.schemaVersion = schemaVersion
        self.hostname = hostname
        self.accountLogin = accountLogin
        self.capturedAt = capturedAt
        self.completeness = completeness
        self.repositoryScope = repositoryScope
        self.availableRepositories = availableRepositories
        self.waitingForReview = waitingForReview
        self.authoredPullRequests = authoredPullRequests
    }
}

public extension WorkloadSnapshot {
    func mergingConfirmedUpdates(into previous: WorkloadSnapshot?) -> WorkloadSnapshot {
        guard let previous,
              previous.hostname.caseInsensitiveCompare(hostname) == .orderedSame,
              previous.accountLogin.caseInsensitiveCompare(accountLogin) == .orderedSame,
              previous.repositoryScope == repositoryScope else {
            return self
        }

        let confirmedIDs = Set(waitingForReview.map(\.id) + authoredPullRequests.map(\.id))
        let mergedWaiting = Self.merge(
            confirmed: waitingForReview,
            retained: previous.waitingForReview.filter { !confirmedIDs.contains($0.id) }
        )
        let mergedAuthored = Self.merge(
            confirmed: authoredPullRequests,
            retained: previous.authoredPullRequests.filter { !confirmedIDs.contains($0.id) }
        )
        let repositoryByID = Dictionary(
            (previous.availableRepositories + availableRepositories).map { ($0.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )

        return WorkloadSnapshot(
            schemaVersion: schemaVersion,
            hostname: hostname,
            accountLogin: accountLogin,
            capturedAt: capturedAt,
            completeness: .partial,
            repositoryScope: repositoryScope,
            availableRepositories: repositoryByID.values.sorted { $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending },
            waitingForReview: mergedWaiting,
            authoredPullRequests: mergedAuthored
        )
    }

    private static func merge(
        confirmed: [PullRequestPresentation],
        retained: [PullRequestPresentation]
    ) -> [PullRequestPresentation] {
        (confirmed + retained).sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }
}
