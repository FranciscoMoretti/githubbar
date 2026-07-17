import AppKit
import GitHubBarCore
import SwiftUI

struct PullRequestRow: View {
    let pullRequest: PullRequestPresentation
    let showsRepository: Bool

    var body: some View {
        Button {
            NSWorkspace.shared.open(pullRequest.url)
        } label: {
            HStack(alignment: .center, spacing: 6) {
                pullRequestStatus
                VStack(alignment: .leading, spacing: 2) {
                    Text(pullRequest.title)
                        .font(.system(size: 11.5, weight: .regular))
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text(metadataLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 3)
                        if !pullRequest.reviewers.isEmpty {
                            ReviewerRosterView(reviewers: pullRequest.reviewers)
                        }
                    }
                }
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(true)
        .contextMenu {
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pullRequest.url.absoluteString, forType: .string)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this pull request on GitHub")
    }

    private var pullRequestStatus: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Circle()
                .fill(pullRequest.isDraft ? Color.clear : Color.green)
                .stroke(pullRequest.isDraft ? Color.secondary : Color.clear, lineWidth: 1)
                .frame(width: 5, height: 5)
                .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                .offset(x: 0.5, y: 0.5)
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel(pullRequest.isDraft ? "Draft pull request" : "Open pull request")
    }

    private var metadataLabel: String {
        let numberAndTime = "#\(pullRequest.number) · \(pullRequest.updatedAt.formatted(.relative(presentation: .numeric)))"
        return showsRepository
            ? "\(pullRequest.repositoryNameWithOwner) · \(numberAndTime)"
            : numberAndTime
    }

    private var accessibilityLabel: String {
        let status = pullRequest.isDraft ? "Draft pull request" : "Open pull request"
        let reviewerNames = pullRequest.reviewers.map(\.displayName).joined(separator: ", ")
        let reviewers = reviewerNames.isEmpty ? "No reviewers" : "Reviewers: \(reviewerNames)"
        return "\(status), \(pullRequest.repositoryNameWithOwner) number \(pullRequest.number), \(pullRequest.title). \(reviewers)."
    }
}

struct ReviewerRosterView: View {
    let reviewers: [ReviewerPresentation]

    var body: some View {
        HStack(spacing: -4) {
            ForEach(Array(reviewers.prefix(4))) { reviewer in
                ReviewerAvatar(reviewer: reviewer)
            }
            if reviewers.count > 4 {
                Text("+\(reviewers.count - 4)")
                    .font(.system(size: 6.5, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .background(.regularMaterial, in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.15), lineWidth: 1) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reviewers: \(reviewers.map(\.displayName).joined(separator: ", "))")
    }
}

private struct ReviewerAvatar: View {
    let reviewer: ReviewerPresentation

    var body: some View {
        Group {
            if let avatarURL = reviewer.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(reviewer.kind == .team ? AnyShape(RoundedRectangle(cornerRadius: 4.5)) : AnyShape(Circle()))
        .overlay {
            if reviewer.kind == .team {
                RoundedRectangle(cornerRadius: 4.5).stroke(.black.opacity(0.55), lineWidth: 1)
            } else {
                Circle().stroke(.black.opacity(0.55), lineWidth: 1)
            }
        }
        .help(reviewer.displayName)
    }

    private var fallback: some View {
        Text(initials)
            .font(.system(size: 6, weight: .bold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
    }

    private var initials: String {
        reviewer.displayName
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}
