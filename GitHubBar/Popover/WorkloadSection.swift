import GitHubBarCore
import SwiftUI

struct WorkloadSection: View {
    let title: String
    let pullRequests: [PullRequestPresentation]
    let emptyMessage: String
    let showsRepository: Bool
    var showsBottomDivider = true

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(pullRequests.count.formatted())
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.bottom, pullRequests.isEmpty ? 1 : 3)

            if pullRequests.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(pullRequests) { pullRequest in
                    PullRequestRow(pullRequest: pullRequest, showsRepository: showsRepository)
                }
            }
        }
        .padding(.vertical, pullRequests.isEmpty ? 8 : 11)
        .overlay(alignment: .bottom) {
            if showsBottomDivider { Divider() }
        }
        .accessibilityElement(children: .contain)
    }
}
