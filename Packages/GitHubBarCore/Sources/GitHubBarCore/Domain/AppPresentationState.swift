import Foundation

public struct AppPresentationState: Codable, Equatable, Sendable {
    public var accountConnection: AccountConnectionPresentation
    public var refreshHealth: RefreshHealthPresentation
    public var repositoryScope: RepositoryScope
    public var availableRepositories: [RepositoryChoice]
    public var waitingForReview: [PullRequestPresentation]
    public var authoredPullRequests: [PullRequestPresentation]
    public var lastUpdatedAt: Date?
    public var isRefreshing: Bool

    public init(
        accountConnection: AccountConnectionPresentation,
        refreshHealth: RefreshHealthPresentation,
        repositoryScope: RepositoryScope,
        availableRepositories: [RepositoryChoice],
        waitingForReview: [PullRequestPresentation],
        authoredPullRequests: [PullRequestPresentation],
        lastUpdatedAt: Date?,
        isRefreshing: Bool
    ) {
        self.accountConnection = accountConnection
        self.refreshHealth = refreshHealth
        self.repositoryScope = repositoryScope
        self.availableRepositories = availableRepositories
        self.waitingForReview = waitingForReview
        self.authoredPullRequests = authoredPullRequests
        self.lastUpdatedAt = lastUpdatedAt
        self.isRefreshing = isRefreshing
    }

    public static let empty = AppPresentationState(
        accountConnection: .notChecked,
        refreshHealth: .idle,
        repositoryScope: .all,
        availableRepositories: [],
        waitingForReview: [],
        authoredPullRequests: [],
        lastUpdatedAt: nil,
        isRefreshing: false
    )

    public var reviewCount: Int {
        waitingForReview.count
    }

    public var reviewCountAccessibilityLabel: String {
        switch reviewCount {
        case 0:
            "No pull requests waiting for your review"
        case 1:
            "1 pull request waiting for your review"
        default:
            "\(reviewCount) pull requests waiting for your review"
        }
    }
}

public enum AccountConnectionPresentation: Codable, Equatable, Sendable {
    case notChecked
    case checking
    case connectionRequired(AccountConnectionProblem)
    case selectionRequired([AccountCandidate])
    case connected(login: String, accessCoverage: AccessCoverage)
}

public enum AccountConnectionProblem: String, Codable, Equatable, Sendable {
    case cliMissing
    case authenticationRequired
    case incompleteAccess
    case unavailable
}

public struct AccountCandidate: Codable, Equatable, Identifiable, Sendable {
    public let login: String
    public let hostname: String

    public init(login: String, hostname: String) {
        self.login = login
        self.hostname = hostname
    }

    public var id: String { "\(hostname)/\(login)" }
}

public struct AccessCoverage: Codable, Equatable, Sendable {
    public let isComplete: Bool
    public let summary: String?

    public init(isComplete: Bool, summary: String? = nil) {
        self.isComplete = isComplete
        self.summary = summary
    }
}

public enum RefreshHealthPresentation: Codable, Equatable, Sendable {
    case idle
    case cached
    case fresh
    case partial(message: String)
    case failed(message: String)
    case rateLimited(until: Date?)
}
