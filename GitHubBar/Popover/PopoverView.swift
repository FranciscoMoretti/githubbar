import AppKit
import GitHubBarCore
import SwiftUI

struct PopoverView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            insetDivider
            if isConnected {
                RepositoryScopeControl(appModel: appModel)
                ScrollView {
                    VStack(spacing: 0) {
                        if isInitialLoading {
                            InitialWorkloadLoadingView()
                        } else if let banner = RefreshHealthBanner.Model(state: appModel.state) {
                            RefreshHealthBanner(model: banner) {
                                appModel.send(.manualRefresh)
                            }
                        }
                        if case let .connected(_, accessCoverage) = appModel.state.accountConnection,
                           !accessCoverage.isComplete {
                            AccessCoverageBanner(accessCoverage: accessCoverage)
                        }
                        if !isInitialLoading {
                            WorkloadSection(
                                title: "Waiting for my review",
                                pullRequests: appModel.state.waitingForReview,
                                emptyMessage: "Nothing is waiting for your review.",
                                showsRepository: showsRepositoryInRows
                            )
                            WorkloadSection(
                                title: "My PRs",
                                pullRequests: appModel.state.authoredPullRequests,
                                emptyMessage: "You have no open pull requests.",
                                showsRepository: showsRepositoryInRows
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                }
            } else {
                AccountConnectionView(
                    accountConnection: appModel.state.accountConnection,
                    send: appModel.send
                )
            }
            footer
        }
        .frame(width: 364)
        .frame(minHeight: 470, idealHeight: 520, maxHeight: 760)
        .background(VisualEffectBackground())
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("GitHubBar")
                    .font(.system(size: 14, weight: .bold))
                Text(updatedLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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
            MenuActionRow(title: "Settings…", systemImage: "gearshape", shortcut: "⌘ ,") {}
            MenuActionRow(title: "About GitHubBar", systemImage: "info.circle") {
                NSApp.orderFrontStandardAboutPanel(nil)
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
        case .cached, .partial, .failed, .rateLimited:
            return "Cached \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
        case .idle, .fresh:
            return "Updated \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
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
        if case let .selected(repositoryIDs) = appModel.state.repositoryScope,
           repositoryIDs.count == 1 {
            return false
        }
        return true
    }
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

private struct RefreshHealthBanner: View {
    struct Model {
        let icon: String
        let title: String
        let detail: String
        let tint: Color
        let showsProgress: Bool
        let offersRetry: Bool

        init?(state: AppPresentationState) {
            if state.isRefreshing, state.lastUpdatedAt != nil {
                icon = "arrow.clockwise"
                title = "Refreshing"
                detail = "Showing your current list while GitHub updates it."
                tint = .secondary
                showsProgress = true
                offersRetry = false
                return
            }

            switch state.refreshHealth {
            case .cached:
                icon = "clock.arrow.circlepath"
                title = "Showing saved data"
                detail = "GitHubBar will refresh this list in the background."
                tint = .secondary
                showsProgress = false
                offersRetry = false
            case let .partial(message):
                icon = "exclamationmark.triangle"
                title = "Some data may be stale"
                detail = message
                tint = .yellow
                showsProgress = false
                offersRetry = true
            case let .rateLimited(until):
                icon = "hourglass"
                title = "GitHub rate limit reached"
                detail = until.map { "Automatic retry after \($0.formatted(date: .omitted, time: .shortened))." }
                    ?? "GitHubBar will retry automatically."
                tint = .orange
                showsProgress = false
                offersRetry = false
            case let .failed(message):
                icon = "wifi.exclamationmark"
                title = "Refresh failed"
                detail = message + " Your previous list is still shown."
                tint = .red
                showsProgress = false
                offersRetry = true
            case .idle, .fresh:
                return nil
            }
        }
    }

    let model: Model
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if model.showsProgress {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: model.icon)
                    .foregroundStyle(model.tint)
                    .frame(width: 13)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(model.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if model.offersRetry {
                Button("Retry", action: retry)
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(9)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.10))
        }
        .padding(.top, 7)
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
