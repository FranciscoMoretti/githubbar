import AppKit
import GitHubBarCore
import SwiftUI

struct PopoverView: View {
    static let preferredWidth: CGFloat = 364
    static let fallbackHeight: CGFloat = 700
    static let minimumResponsiveHeight: CGFloat = 640
    static let maximumHeight: CGFloat = 900
    static let screenEdgeClearance: CGFloat = 120

    static func resolvedHeight(forVisibleScreenHeight visibleScreenHeight: CGFloat?) -> CGFloat {
        guard let visibleScreenHeight else { return Self.fallbackHeight }
        return min(
            Self.maximumHeight,
            max(Self.minimumResponsiveHeight, floor(visibleScreenHeight - Self.screenEdgeClearance))
        )
    }

    @Bindable var appModel: AppModel
    let actions: AppActions
    let avatarImageCache: AvatarImageCache

    init(
        appModel: AppModel,
        actions: AppActions = AppActions(),
        avatarImageCache: AvatarImageCache
    ) {
        self.appModel = appModel
        self.actions = actions
        self.avatarImageCache = avatarImageCache
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            insetDivider
            if isConnected {
                RepositoryScopeControl(appModel: appModel)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if isInitialLoading {
                            InitialWorkloadLoadingView()
                        }
                        if case let .connected(_, accessCoverage) = appModel.state.accountConnection,
                           !accessCoverage.isComplete {
                            AccessCoverageBanner(accessCoverage: accessCoverage)
                        }
                        if !isInitialLoading {
                            WorkloadSection(
                                title: "Waiting for my review",
                                pullRequests: appModel.state.needsYourReview,
                                emptyMessage: "Nothing is waiting for your review.",
                                showsRepository: showsRepositoryInRows
                            )
                            WorkloadSection(
                                title: "My PRs",
                                pullRequests: appModel.state.authoredPullRequests,
                                emptyMessage: "You have no open pull requests.",
                                showsRepository: showsRepositoryInRows,
                                showsBottomDivider: false
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .id(repositoryScopeScrollIdentity)
            } else {
                AccountConnectionView(
                    accountConnection: appModel.state.accountConnection,
                    send: appModel.send
                )
            }
            footer
        }
        .frame(width: Self.preferredWidth)
        .frame(minHeight: 470, idealHeight: Self.fallbackHeight, maxHeight: Self.maximumHeight)
        .background(VisualEffectBackground())
        .environmentObject(avatarImageCache)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("GitHubBar")
                    .font(.system(size: 14, weight: .bold))
                Text(updatedLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(updatedLabelColor)
                    .help(updatedLabelHelp)
                    .accessibilityLabel("Refresh status: \(updatedLabel)")
            }
            Spacer(minLength: 8)
            Text(accountLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    private var insetDivider: some View {
        Divider().padding(.horizontal, 18)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 18)
            if isConnected {
                MenuActionRow(title: "Refresh", systemImage: "arrow.clockwise", shortcut: "⌘ R") {
                    appModel.send(.manualRefresh)
                }
            }
            MenuActionRow(title: "Settings…", systemImage: "gearshape", shortcut: "⌘ ,") {
                actions.openSettings()
            }
            MenuActionRow(title: "About GitHubBar", systemImage: "info.circle") {
                actions.openAbout()
            }
            MenuActionRow(title: "Quit", systemImage: "rectangle.portrait.and.arrow.right", shortcut: "⌘ Q") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 5)
    }

    private var updatedLabel: String {
        switch appModel.state.accountConnection {
        case .notChecked, .checking:
            return "Checking GitHub CLI…"
        case .connectionRequired:
            return "Account connection required"
        case .selectionRequired:
            return "Choose monitored account"
        case .connected:
            break
        }
        if appModel.state.isRefreshing { return "Refreshing…" }
        guard let lastUpdatedAt = appModel.state.lastUpdatedAt else { return "Ready" }
        switch appModel.state.refreshHealth {
        case .restoredSnapshot:
            return "Snapshot \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
        case .partial:
            return "Partial update · \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
        case .failed:
            return "Refresh failed · \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
        case .rateLimited:
            return "Rate limited · \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
        case .idle, .fresh:
            return "Updated \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
        }
    }

    private var updatedLabelColor: Color {
        switch appModel.state.refreshHealth {
        case .partial, .rateLimited:
            .orange
        case .failed:
            .red
        case .idle, .restoredSnapshot, .fresh:
            .secondary
        }
    }

    private var updatedLabelHelp: String {
        switch appModel.state.refreshHealth {
        case .idle, .fresh:
            "The active workload is up to date."
        case .restoredSnapshot:
            "Showing the saved Snapshot while GitHubBar reconciles in the background."
        case let .partial(message), let .failed(message):
            message
        case let .rateLimited(until):
            until.map { "GitHubBar will retry after \($0.formatted(date: .omitted, time: .shortened))." }
                ?? "GitHubBar will retry automatically."
        }
    }

    private var accountLabel: String {
        switch appModel.state.accountConnection {
        case let .connected(login, _):
            return "@\(login) ›"
        case .selectionRequired:
            return "GitHub.com ›"
        case .notChecked, .checking, .connectionRequired:
            return "GitHub CLI ›"
        }
    }

    private var isConnected: Bool {
        if case .connected = appModel.state.accountConnection { return true }
        return false
    }

    private var isInitialLoading: Bool {
        isConnected && appModel.state.isRefreshing && appModel.state.lastUpdatedAt == nil
    }

    private var showsRepositoryInRows: Bool {
        if appModel.state.repositoryScope == .pinned,
           appModel.state.pinnedRepositoryIDs.count == 1 {
            return false
        }
        return true
    }

    private var repositoryScopeScrollIdentity: RepositoryScopeScrollIdentity {
        switch appModel.state.repositoryScope {
        case .all:
            .all
        case .pinned:
            .pinned
        }
    }
}

private enum RepositoryScopeScrollIdentity: Hashable {
    case all
    case pinned
}

private struct InitialWorkloadLoadingView: View {
    var body: some View {
        VStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
            Text("Loading your pull requests…")
                .font(.system(size: 11, weight: .medium))
            Text("GitHubBar will keep this workload available for instant launches after the first refresh.")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .accessibilityElement(children: .combine)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct AccessCoverageBanner: View {
    let accessCoverage: AccessCoverage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Incomplete access")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(accessCoverage.summary ?? "Some organizations or repositories may not be visible.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.12))
        }
        .padding(.top, 7)
        .accessibilityElement(children: .combine)
    }
}
