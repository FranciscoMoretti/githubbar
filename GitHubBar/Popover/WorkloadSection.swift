import GitHubBarCore
import SwiftUI

struct WorkloadSection: View {
    let title: String
    let pullRequests: [PullRequestPresentation]
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(pullRequests.count.formatted())
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if pullRequests.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 9)
            } else {
                ForEach(pullRequests) { pullRequest in
                    PullRequestRow(pullRequest: pullRequest)
                }
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}
