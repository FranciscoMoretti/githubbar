import GitHubBarCore
import SwiftUI

enum RepositoryScopeControlStyle {
    case popover
    case settings
}

struct RepositoryScopeControl: View {
    @Bindable var appModel: AppModel
    let style: RepositoryScopeControlStyle
    @State private var isPickerPresented = false

    init(appModel: AppModel, style: RepositoryScopeControlStyle = .popover) {
        self.appModel = appModel
        self.style = style
    }

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style == .popover ? "Repositories" : "Repository scope")
                    if style == .settings {
                        Text("Saved locally on this Mac")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(scopeLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focusEffectDisabled(style == .popover)
        .padding(.horizontal, style == .popover ? 18 : 0)
        .frame(height: style == .popover ? 32 : 40)
        .accessibilityLabel("Choose repositories. Current selection: \(scopeLabel)")
        .popover(
            isPresented: $isPickerPresented,
            arrowEdge: style == .popover ? .leading : .top
        ) {
            RepositoryPicker(
                repositories: appModel.state.availableRepositories,
                currentScope: appModel.state.repositoryScope
            ) { scope in
                appModel.send(.selectRepositoryScope(scope))
            }
        }
    }

    private var scopeLabel: String {
        switch appModel.state.repositoryScope {
        case .all:
            return "All repositories"
        case let .selected(repositoryIDs):
            if repositoryIDs.isEmpty { return "No repositories" }
            if repositoryIDs.count == 1,
               let repositoryID = repositoryIDs.first,
               let repository = appModel.state.availableRepositories.first(where: { $0.id == repositoryID }) {
                return repository.nameWithOwner
            }
            return repositoryIDs.count == 1 ? "1 unavailable" : "\(repositoryIDs.count) selected"
        }
    }
}

private struct RepositoryPicker: View {
    let repositories: [RepositoryChoice]
    let currentScope: RepositoryScope
    let onSelect: (RepositoryScope) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @FocusState private var searchIsFocused: Bool

    init(
        repositories: [RepositoryChoice],
        currentScope: RepositoryScope,
        onSelect: @escaping (RepositoryScope) -> Void
    ) {
        self.repositories = repositories
        self.currentScope = currentScope
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Repositories")
                    .font(.system(size: 13, weight: .semibold))
                Text("This selection is saved on this Mac and controls both lists and the Review count.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                TextField("Search repositories", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchIsFocused)
                    .accessibilityLabel("Search repositories")
            }
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    repositoryOption(
                        title: "All repositories",
                        subtitle: "\(repositories.count) accessible",
                        isSelected: currentScope == .all
                    ) {
                        select(.all)
                    }

                    ForEach(filteredRepositories) { repository in
                        repositoryOption(
                            title: repository.nameWithOwner,
                            subtitle: nil,
                            isSelected: selectedRepositoryIDs.contains(repository.id)
                        ) {
                            select(.selected([repository.id]))
                        }
                    }

                    if filteredRepositories.isEmpty {
                        Text("No repositories match your search.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                    }
                }
                .padding(8)
            }

            if unavailableSelectionCount > 0 {
                Label(
                    "\(unavailableSelectionCount) selected \(unavailableSelectionCount == 1 ? "repository is" : "repositories are") no longer accessible.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 9))
                .foregroundStyle(.yellow)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

        }
        .frame(width: 330, height: 410)
        .onAppear { searchIsFocused = true }
    }

    private var filteredRepositories: [RepositoryChoice] {
        guard !searchText.isEmpty else { return repositories }
        return repositories.filter {
            $0.nameWithOwner.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedRepositoryIDs: Set<String> {
        currentScope.selectedRepositoryIDs
    }

    private var unavailableSelectionCount: Int {
        let availableIDs = Set(repositories.map(\.id))
        return selectedRepositoryIDs.subtracting(availableIDs).count
    }

    private func select(_ scope: RepositoryScope) {
        onSelect(scope)
        dismiss()
    }

    private func repositoryOption(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(true)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("\(title), \(isSelected ? "selected" : "not selected")")
    }
}
