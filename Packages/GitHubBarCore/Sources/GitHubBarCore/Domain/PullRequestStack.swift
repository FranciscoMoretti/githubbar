import Foundation

public struct PullRequestStack: Equatable, Identifiable, Sendable {
    public let id: String
    public let pullRequests: [PullRequestPresentation]

    public init(id: String, pullRequests: [PullRequestPresentation]) {
        self.id = id
        self.pullRequests = pullRequests
    }

    public var root: PullRequestPresentation? {
        pullRequests.first
    }

    public var githubCompareURL: URL? {
        guard let root = pullRequests.first,
              let top = pullRequests.last,
              let baseRefName = root.baseRefName,
              let headRefName = top.headRefName,
              let encodedBaseRefName = percentEncodedRefName(baseRefName),
              let encodedHeadRefName = percentEncodedRefName(headRefName),
              let repositoryNameWithOwner = pullRequests.first?.repositoryNameWithOwner,
              pullRequests.allSatisfy({ $0.repositoryNameWithOwner == repositoryNameWithOwner }) else {
            return nil
        }
        return URL(
            string: "https://github.com/\(repositoryNameWithOwner)/compare/" +
                "\(encodedBaseRefName)...\(encodedHeadRefName)"
        )
    }

    private func percentEncodedRefName(_ refName: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return refName.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

public enum PullRequestStackResolver {
    public static func stacks(in pullRequests: [PullRequestPresentation]) -> [PullRequestStack] {
        let pullRequestsByID = pullRequests.reduce(into: [String: PullRequestPresentation]()) {
            result, pullRequest in
            result[pullRequest.id] = pullRequest
        }
        let headOwners = Dictionary(grouping: pullRequests.compactMap { pullRequest -> (BranchKey, String)? in
            guard let headRefName = pullRequest.headRefName else { return nil }
            return (
                BranchKey(
                    repositoryID: pullRequest.headRepositoryID ?? pullRequest.repositoryID,
                    refName: headRefName
                ),
                pullRequest.id
            )
        }, by: \.0).compactMapValues { matches in
            matches.count == 1 ? matches[0].1 : nil
        }

        var parentByChildID: [String: String] = [:]
        var childIDsByParentID: [String: [String]] = [:]
        for pullRequest in pullRequests {
            guard let baseRefName = pullRequest.baseRefName,
                  let parentID = headOwners[
                    BranchKey(repositoryID: pullRequest.repositoryID, refName: baseRefName)
                  ],
                  parentID != pullRequest.id else {
                continue
            }
            parentByChildID[pullRequest.id] = parentID
            childIDsByParentID[parentID, default: []].append(pullRequest.id)
        }

        let linkedIDs = Set(parentByChildID.keys).union(parentByChildID.values)
        let rootIDs = linkedIDs.filter { parentByChildID[$0] == nil }.sorted {
            pullRequestOrder(pullRequestsByID[$0], pullRequestsByID[$1])
        }

        var visited: Set<String> = []
        var stacks: [PullRequestStack] = []
        for rootID in rootIDs {
            let orderedIDs = depthFirstOrder(
                from: rootID,
                childIDsByParentID: childIDsByParentID,
                pullRequestsByID: pullRequestsByID,
                visited: &visited
            )
            let hasBranching = orderedIDs.contains {
                (childIDsByParentID[$0]?.count ?? 0) > 1
            }
            let members = orderedIDs.compactMap { pullRequestsByID[$0] }
            if members.count > 1, !hasBranching {
                stacks.append(PullRequestStack(id: rootID, pullRequests: members))
            }
        }
        return stacks
    }

    private static func depthFirstOrder(
        from pullRequestID: String,
        childIDsByParentID: [String: [String]],
        pullRequestsByID: [String: PullRequestPresentation],
        visited: inout Set<String>
    ) -> [String] {
        guard visited.insert(pullRequestID).inserted else { return [] }
        let childIDs = (childIDsByParentID[pullRequestID] ?? []).sorted {
            pullRequestOrder(pullRequestsByID[$0], pullRequestsByID[$1])
        }
        return [pullRequestID] + childIDs.flatMap {
            depthFirstOrder(
                from: $0,
                childIDsByParentID: childIDsByParentID,
                pullRequestsByID: pullRequestsByID,
                visited: &visited
            )
        }
    }

    private static func pullRequestOrder(
        _ lhs: PullRequestPresentation?,
        _ rhs: PullRequestPresentation?
    ) -> Bool {
        guard let lhs, let rhs else { return lhs != nil }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.number < rhs.number
    }

    private struct BranchKey: Hashable {
        let repositoryID: String
        let refName: String
    }
}
