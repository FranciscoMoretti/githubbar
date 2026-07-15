import Foundation

public struct PullRequestPresentation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let repositoryID: String
    public let repositoryNameWithOwner: String
    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let updatedAt: Date
    public let reviewers: [ReviewerPresentation]

    public init(
        id: String,
        repositoryID: String,
        repositoryNameWithOwner: String,
        number: Int,
        title: String,
        url: URL,
        isDraft: Bool,
        updatedAt: Date,
        reviewers: [ReviewerPresentation]
    ) {
        self.id = id
        self.repositoryID = repositoryID
        self.repositoryNameWithOwner = repositoryNameWithOwner
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.updatedAt = updatedAt
        self.reviewers = reviewers
    }
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
