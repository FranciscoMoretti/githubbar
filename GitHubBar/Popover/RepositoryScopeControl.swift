import GitHubBarCore
import SwiftUI

struct RepositoryScopeControl: View {
    @Bindable var appModel: AppModel
    @State private var isPickerPresented = false

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text("Repositories")
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
        .focusEffectDisabled()
        .padding(.horizontal, 18)
        .frame(height: 32)
        .accessibilityLabel("Choose repositories. Current selection: \(scopeLabel)")
        .popover(
            isPresented: $isPickerPresented,
            arrowEdge: .leading
        ) {
            RepositoryPicker(
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
        case .pinned:
            return "Pinned repositories"
        }
    }
}

private struct RepositoryPicker: View {
    let currentScope: RepositoryScope
    let onSelect: (RepositoryScope) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        currentScope: RepositoryScope,
        onSelect: @escaping (RepositoryScope) -> Void
    ) {
        self.currentScope = currentScope
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Repository view")
                    .font(.system(size: 13, weight: .semibold))
                Text("Pins are configured in Settings and saved on this Mac.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            VStack(spacing: 2) {
                repositoryOption(title: "All repositories", isSelected: currentScope == .all) {
                    select(.all)
                }
                repositoryOption(title: "Pinned repositories", isSelected: currentScope == .pinned) {
                    select(.pinned)
                }
            }
            .padding(8)
        }
        .frame(width: 280)
    }

    private func select(_ scope: RepositoryScope) {
        onSelect(scope)
        dismiss()
    }

    private func repositoryOption(
        title: String,
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
