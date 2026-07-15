import AppKit
import GitHubBarCore
import SwiftUI

struct PullRequestRow: View {
    let pullRequest: PullRequestPresentation

    var body: some View {
        Button {
            NSWorkspace.shared.open(pullRequest.url)
        } label: {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13))
                    .foregroundStyle(pullRequest.isDraft ? Color.secondary : Color.green)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pullRequest.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Text("\(pullRequest.repositoryNameWithOwner) · #\(pullRequest.number)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pullRequest.url.absoluteString, forType: .string)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let status = pullRequest.isDraft ? "Draft pull request" : "Open pull request"
        let reviewerNames = pullRequest.reviewers.map(\.displayName).joined(separator: ", ")
        let reviewers = reviewerNames.isEmpty ? "No reviewers" : "Reviewers: \(reviewerNames)"
        return "\(status), \(pullRequest.repositoryNameWithOwner) number \(pullRequest.number), \(pullRequest.title). \(reviewers)."
    }
}
