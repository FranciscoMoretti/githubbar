import GitHubBarCore
import SwiftUI

struct PinnedRepositoriesSettingsView: View {
    @Bindable var appModel: AppModel
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose the repositories shown by the Pinned tab. Pins are saved only on this Mac.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            TextField("Search repositories", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search repositories")

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Pinned")
                        .frame(width: 54, alignment: .leading)
                    Text("Repository")
                    Spacer()
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 26)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredRows.enumerated()), id: \.element.id) { index, row in
                            repositoryRow(row, alternates: index.isMultiple(of: 2))
                        }

                        if filteredRows.isEmpty {
                            Text("No repositories match your search.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        }
                    }
                }
            }
            .frame(height: 250)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(.separator.opacity(0.7)) }

            HStack {
                Text("\(appModel.state.availableRepositories.count) repositories")
                Spacer()
                Text("\(appModel.state.pinnedRepositoryIDs.count) pinned")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
    }

    private var filteredRows: [PinnedRepositorySettingsRow] {
        let available = appModel.state.availableRepositories.map {
            PinnedRepositorySettingsRow(repository: $0, isAvailable: true)
        }
        let availableIDs = Set(available.map(\.id))
        let unavailable = appModel.state.pinnedRepositories
            .filter { !availableIDs.contains($0.id) }
            .map {
                PinnedRepositorySettingsRow(
                    repository: RepositoryChoice(id: $0.id, nameWithOwner: $0.nameWithOwner),
                    isAvailable: false
                )
            }
        return (available + unavailable)
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func repositoryRow(_ row: PinnedRepositorySettingsRow, alternates: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle("Pin \(row.name)", isOn: pinBinding(for: row.repository))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                if !row.isAvailable {
                    Text("Currently unavailable")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: row.isAvailable ? 30 : 38)
        .background(alternates ? Color.primary.opacity(0.035) : Color.clear)
        .contentShape(Rectangle())
    }

    private func pinBinding(for repository: RepositoryChoice) -> Binding<Bool> {
        Binding(
            get: { appModel.state.pinnedRepositoryIDs.contains(repository.id) },
            set: { isPinned in
                guard isPinned != appModel.state.pinnedRepositoryIDs.contains(repository.id) else { return }
                appModel.send(.togglePinnedRepository(repository))
            }
        )
    }
}

private struct PinnedRepositorySettingsRow: Identifiable {
    let repository: RepositoryChoice
    let isAvailable: Bool

    var id: String { repository.id }
    var name: String { repository.nameWithOwner }
}
