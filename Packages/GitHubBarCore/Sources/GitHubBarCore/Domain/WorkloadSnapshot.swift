import Foundation

public struct WorkloadSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public enum Completeness: String, Codable, Equatable, Sendable {
        case complete
        case partial
    }

    public let schemaVersion: Int
    public let hostname: String
    public let accountLogin: String
    public let capturedAt: Date
    public let completeness: Completeness
    public let availableRepositories: [RepositoryChoice]
    public let needsYourReview: [PullRequestPresentation]
    public let authoredPullRequests: [PullRequestPresentation]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, hostname, accountLogin, capturedAt, completeness, availableRepositories
        case needsYourReview = "waitingForReview"
        case authoredPullRequests
    }

    public init(
        schemaVersion: Int = WorkloadSnapshot.currentSchemaVersion,
        hostname: String,
        accountLogin: String,
        capturedAt: Date,
        completeness: Completeness,
        availableRepositories: [RepositoryChoice],
        needsYourReview: [PullRequestPresentation],
        authoredPullRequests: [PullRequestPresentation]
    ) {
        self.schemaVersion = schemaVersion
        self.hostname = hostname
        self.accountLogin = accountLogin
        self.capturedAt = capturedAt
        self.completeness = completeness
        self.availableRepositories = availableRepositories
        self.needsYourReview = needsYourReview
        self.authoredPullRequests = authoredPullRequests
    }
}

public extension WorkloadSnapshot {
    func mergingConfirmedUpdates(into previous: WorkloadSnapshot?) -> WorkloadSnapshot {
        guard let previous,
              previous.hostname.caseInsensitiveCompare(hostname) == .orderedSame,
              previous.accountLogin.caseInsensitiveCompare(accountLogin) == .orderedSame else {
            return self
        }

        let confirmedIDs = Set(needsYourReview.map(\.id) + authoredPullRequests.map(\.id))
        let mergedWaiting = Self.merge(
            confirmed: needsYourReview,
            retained: previous.needsYourReview.filter { !confirmedIDs.contains($0.id) },
            mostRecentFirst: false
        )
        let mergedAuthored = Self.merge(
            confirmed: authoredPullRequests,
            retained: previous.authoredPullRequests.filter { !confirmedIDs.contains($0.id) },
            mostRecentFirst: true
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
            availableRepositories: repositoryByID.values.sorted { $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending },
            needsYourReview: mergedWaiting,
            authoredPullRequests: mergedAuthored
        )
    }

    private static func merge(
        confirmed: [PullRequestPresentation],
        retained: [PullRequestPresentation],
        mostRecentFirst: Bool
    ) -> [PullRequestPresentation] {
        (confirmed + retained).sorted {
            if $0.updatedAt != $1.updatedAt {
                return mostRecentFirst ? $0.updatedAt > $1.updatedAt : $0.updatedAt < $1.updatedAt
            }
            return $0.id < $1.id
        }
    }
}
