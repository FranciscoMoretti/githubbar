import Foundation

public enum RepositoryScope: Codable, Equatable, Sendable {
    case all
    case selected(Set<String>)

    public var selectedRepositoryIDs: Set<String> {
        switch self {
        case .all: []
        case let .selected(repositoryIDs): repositoryIDs
        }
    }
}

public struct RepositoryChoice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let nameWithOwner: String

    public init(id: String, nameWithOwner: String) {
        self.id = id
        self.nameWithOwner = nameWithOwner
    }
}
