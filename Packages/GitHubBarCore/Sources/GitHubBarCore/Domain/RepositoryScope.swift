import Foundation

public enum RepositoryScope: Codable, Equatable, Sendable {
    case all
    case pinned

    public func includes(repositoryID: String, pinnedRepositoryIDs: Set<String>) -> Bool {
        switch self {
        case .all:
            true
        case .pinned:
            pinnedRepositoryIDs.contains(repositoryID)
        }
    }
}

public struct PinnedRepository: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let nameWithOwner: String

    public init(id: String, nameWithOwner: String) {
        self.id = id
        self.nameWithOwner = nameWithOwner
    }

    public static func == (lhs: PinnedRepository, rhs: PinnedRepository) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
