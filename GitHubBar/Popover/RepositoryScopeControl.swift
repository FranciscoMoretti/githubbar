import GitHubBarCore
import SwiftUI

struct RepositoryScopeControl: View {
    @Bindable var appModel: AppModel

    var body: some View {
        Menu {
            Button("All repositories") {
                appModel.send(.selectRepositoryScope(.all))
            }
            ForEach(appModel.state.availableRepositories) { repository in
                Button(repository.nameWithOwner) {
                    appModel.send(.selectRepositoryScope(.selected([repository.id])))
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text("Repositories")
                Spacer()
                Text(scopeLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .frame(height: 34)
        .accessibilityLabel("Choose repositories. Current selection: \(scopeLabel)")
    }

    private var scopeLabel: String {
        switch appModel.state.repositoryScope {
        case .all:
            "All repositories"
        case let .selected(repositoryIDs):
            if repositoryIDs.count == 1,
               let repositoryID = repositoryIDs.first,
               let repository = appModel.state.availableRepositories.first(where: { $0.id == repositoryID }) {
                repository.nameWithOwner
            } else {
                "\(repositoryIDs.count) selected"
            }
        }
    }
}
