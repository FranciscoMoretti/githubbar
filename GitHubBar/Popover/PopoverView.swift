import AppKit
import GitHubBarCore
import SwiftUI

struct PopoverView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            insetDivider
            RepositoryScopeControl(appModel: appModel)
            ScrollView {
                VStack(spacing: 0) {
                    WorkloadSection(
                        title: "Waiting for my review",
                        pullRequests: appModel.state.waitingForReview,
                        emptyMessage: "Nothing is waiting for your review."
                    )
                    WorkloadSection(
                        title: "My PRs",
                        pullRequests: appModel.state.authoredPullRequests,
                        emptyMessage: "You have no open pull requests."
                    )
                }
                .padding(.horizontal, 18)
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
            MenuActionRow(title: "Refresh", systemImage: "arrow.clockwise", shortcut: "⌘ R") {
                appModel.send(.manualRefresh)
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
        if appModel.state.isRefreshing { return "Refreshing…" }
        guard let lastUpdatedAt = appModel.state.lastUpdatedAt else { return "Ready" }
        return "Updated \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
    }

    private var accountLabel: String {
        if case let .connected(login, _) = appModel.state.accountConnection {
            return "@\(login) ›"
        }
        return "Not connected"
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
