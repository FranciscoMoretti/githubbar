import Foundation

public struct PullRequestPresentation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let repositoryID: String
    public let repositoryNameWithOwner: String
    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let author: PullRequestAuthorPresentation?
    public let reviewDecision: PullRequestReviewDecision?
    public let updatedAt: Date
    public let requestedReviewers: [ReviewerPresentation]?
    public let reviewers: [ReviewerPresentation]

    public init(
        id: String,
        repositoryID: String,
        repositoryNameWithOwner: String,
        number: Int,
        title: String,
        url: URL,
        isDraft: Bool,
        author: PullRequestAuthorPresentation? = nil,
        reviewDecision: PullRequestReviewDecision? = nil,
        updatedAt: Date,
        requestedReviewers: [ReviewerPresentation]? = [],
        reviewers: [ReviewerPresentation]
    ) {
        self.id = id
        self.repositoryID = repositoryID
        self.repositoryNameWithOwner = repositoryNameWithOwner
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.author = author
        self.reviewDecision = reviewDecision
        self.updatedAt = updatedAt
        self.requestedReviewers = requestedReviewers
        self.reviewers = reviewers
    }

    public var authoredSection: AuthoredPullRequestSection? {
        if isDraft { return .drafts }
        switch reviewDecision {
        case .changesRequested:
            return .returnedToYou
        case .approved:
            return .approved
        case .reviewRequired:
            return .waitingForReviewers
        case nil:
            guard let requestedReviewers else { return nil }
            return requestedReviewers.isEmpty ? .needsReviewers : .waitingForReviewers
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, repositoryID, repositoryNameWithOwner, number, title, url, isDraft, author
        case reviewDecision, updatedAt, requestedReviewers, reviewers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        repositoryID = try container.decode(String.self, forKey: .repositoryID)
        repositoryNameWithOwner = try container.decode(String.self, forKey: .repositoryNameWithOwner)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(URL.self, forKey: .url)
        isDraft = try container.decode(Bool.self, forKey: .isDraft)
        author = try container.decodeIfPresent(PullRequestAuthorPresentation.self, forKey: .author)
        reviewDecision = try container.decodeIfPresent(PullRequestReviewDecision.self, forKey: .reviewDecision)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        reviewers = try container.decode([ReviewerPresentation].self, forKey: .reviewers)
        requestedReviewers = try container.decodeIfPresent(
            [ReviewerPresentation].self,
            forKey: .requestedReviewers
        )
    }
}

public struct PullRequestAuthorPresentation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let avatarURL: URL?

    public init(id: String, displayName: String, avatarURL: URL?) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}

public enum PullRequestReviewDecision: String, Codable, Equatable, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

public enum AuthoredPullRequestSection: String, Codable, CaseIterable, Equatable, Sendable {
    case returnedToYou
    case needsReviewers
    case waitingForReviewers
    case approved
    case drafts
}

public struct ReviewerPresentation: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case person
        case team
    }

    public let id: String
    public let displayName: String
    public let avatarURL: URL?
    public let kind: Kind

    public init(id: String, displayName: String, avatarURL: URL?, kind: Kind) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.kind = kind
    }
}
