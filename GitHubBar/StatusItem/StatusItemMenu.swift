import AppKit
import GitHubBarCore
import SwiftUI

@MainActor
extension StatusItemController: NSMenuDelegate {
    func configureStatusMenu() {
        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        populateStatusMenu()
    }

    func rebuildStatusMenu() {
        guard !isStatusMenuOpen else { return }
        populateStatusMenu()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        populateStatusMenu()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        isStatusMenuOpen = true
        appModel.send(.setWorkloadSurfaceOpen(true))
    }

    public func menuDidClose(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        isStatusMenuOpen = false
        highlightedStatusMenuItem = nil
        appModel.send(.setWorkloadSurfaceOpen(false))
        rebuildStatusMenu()
    }

    public func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard menu === statusMenu else { return }
        (highlightedStatusMenuItem?.view as? StatusMenuHighlighting)?.setHighlighted(false)
        highlightedStatusMenuItem = nil
        guard let item, item.isEnabled, let view = item.view as? StatusMenuHighlighting else { return }
        highlightedStatusMenuItem = item
        view.setHighlighted(true)
    }

    private func populateStatusMenu() {
        statusMenu.removeAllItems()
        statusMenu.addItem(headerItem())
        statusMenu.addItem(repositoryFilterItem())

        if appModel.state.repositoryScope == .pinned,
           appModel.state.pinnedRepositories.isEmpty {
            addNoPinnedRepositoriesState()
            addActions()
            return
        }

        addSection(
            .needsYourReview,
            pullRequests: appModel.state.needsYourReview
        )
        for authoredSection in AuthoredPullRequestSection.allCases {
            addSection(
                .authored(authoredSection),
                pullRequests: appModel.state.authoredPullRequests.filter {
                    $0.authoredSection == authoredSection
                }
            )
        }
        addSection(
            .legacyMyPRs,
            pullRequests: appModel.state.authoredPullRequests.filter {
                $0.authoredSection == nil
            },
            showsWhenEmpty: false
        )

        addActions()
    }

    private func addNoPinnedRepositoriesState() {
        statusMenu.addItem(.separator())

        let empty = NSMenuItem(
            title: "No pinned repositories",
            action: nil,
            keyEquivalent: ""
        )
        empty.isEnabled = false
        setSubtitle("Choose the repositories you care about on this Mac.", on: empty)
        statusMenu.addItem(empty)

        let manage = NSMenuItem(
            title: "Choose repositories in Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        manage.target = self
        statusMenu.addItem(manage)
    }

    private func addSection(
        _ section: StatusMenuSection,
        pullRequests: [PullRequestPresentation],
        showsWhenEmpty: Bool = true
    ) {
        guard showsWhenEmpty || !pullRequests.isEmpty else { return }
        statusMenu.addItem(.separator())

        let header = NSMenuItem(
            title: "\(section.title)  \(pullRequests.count)",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        statusMenu.addItem(header)

        pullRequests.prefix(Self.pullRequestLimit).forEach {
            statusMenu.addItem(pullRequestItem($0))
        }
        if pullRequests.count > Self.pullRequestLimit {
            statusMenu.addItem(seeAllItem(for: section))
        }
    }

    private func headerItem() -> NSMenuItem {
        let item = NSMenuItem(title: "GitHubBar", action: nil, keyEquivalent: "")
        item.isEnabled = false
        setSubtitle("\(accountLabel) · \(updatedLabel)", on: item)
        return item
    }

    private func repositoryFilterItem() -> NSMenuItem {
        let item = NSMenuItem()
        let view = StatusMenuRepositoryFilter(
            selection: appModel.state.repositoryScope,
            pinnedCount: appModel.state.pinnedRepositoryIDs.count,
            onSelect: { [weak self] scope in
                self?.selectRepositoryScope(scope)
            },
            onManage: { [weak self] in
                self?.statusMenu.cancelTracking()
                self?.actions.openSettings()
            }
        )
        .frame(width: Self.menuWidth, height: 38)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: Self.menuWidth, height: 38)
        item.view = hosting
        item.isEnabled = true
        return item
    }

    private func pullRequestItem(_ pullRequest: PullRequestPresentation) -> NSMenuItem {
        let highlightState = StatusMenuHighlightState()
        let row = StatusMenuPullRequestRow(
            pullRequest: pullRequest,
            highlightState: highlightState
        )
        .environmentObject(avatarImageCache)
        .padding(.horizontal, 11)
        .frame(width: Self.menuWidth, height: Self.pullRequestRowHeight)
        let hosting = StatusMenuRowHostingView(
            rootView: row,
            highlightState: highlightState,
            accessibilityLabel: accessibilityLabel(for: pullRequest)
        ) { [weak self] in
            self?.open(pullRequest.url)
        }
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: Self.menuWidth,
            height: Self.pullRequestRowHeight
        )

        let item = NSMenuItem()
        item.view = hosting
        item.isEnabled = true
        item.target = self
        item.action = #selector(openURL(_:))
        item.representedObject = pullRequest.url as NSURL
        item.toolTip = "\(pullRequest.repositoryNameWithOwner) · #\(pullRequest.number): \(pullRequest.title)"
        return item
    }

    private func seeAllItem(for section: StatusMenuSection) -> NSMenuItem {
        let item = NSMenuItem(
            title: "See all ↗",
            action: #selector(openURL(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = pullRequestSearchURL(for: section) as NSURL
        return item
    }

    private func pullRequestSearchURL(for section: StatusMenuSection) -> URL {
        let login = monitoredAccountLogin ?? "@me"
        var qualifiers = ["is:open", "is:pr"] + section.searchQualifiers.map {
            $0.replacingOccurrences(of: "@me", with: login)
        }
        if appModel.state.repositoryScope == .pinned,
           appModel.state.pinnedRepositoryIDs.count == 1,
           let repositoryID = appModel.state.pinnedRepositoryIDs.first,
           let repository = appModel.state.availableRepositories.first(where: { $0.id == repositoryID }) {
            qualifiers.append("repo:\(repository.nameWithOwner)")
        }
        var components = URLComponents(string: "https://github.com/pulls")!
        components.queryItems = [
            URLQueryItem(name: "q", value: qualifiers.joined(separator: " ")),
        ]
        return components.url!
    }

    private func addActions() {
        statusMenu.addItem(.separator())
        statusMenu.addItem(actionItem("Refresh", selector: #selector(refresh), key: "r"))
        statusMenu.addItem(actionItem("Settings…", selector: #selector(openSettings), key: ","))
        statusMenu.addItem(actionItem("About GitHubBar", selector: #selector(openAbout)))
        statusMenu.addItem(actionItem("Quit", selector: #selector(quit), key: "q"))
        guard let registeredShortcut else { return }
        statusMenu.addItem(.separator())

        let shortcut = NSMenuItem(
            title: "Shortcut to open GitHubBar",
            action: nil,
            keyEquivalent: registeredShortcut.key.keyEquivalent
        )
        shortcut.keyEquivalentModifierMask = registeredShortcut.modifiers
        shortcut.isEnabled = false
        statusMenu.addItem(shortcut)
    }

    private func actionItem(_ title: String, selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func setSubtitle(_ subtitle: String, on item: NSMenuItem) {
        if #available(macOS 14.4, *) {
            item.subtitle = subtitle
        } else {
            item.toolTip = subtitle
        }
    }

    private func accessibilityLabel(for pullRequest: PullRequestPresentation) -> String {
        let author = pullRequest.author.map { "Author: \($0.displayName). " } ?? ""
        let reviewerNames = pullRequest.reviewers.map(\.displayName).joined(separator: ", ")
        let reviewers = reviewerNames.isEmpty ? "No reviewers" : "Reviewers: \(reviewerNames)"
        return "\(pullRequest.repositoryNameWithOwner) number \(pullRequest.number), " +
            "\(pullRequest.title). \(author)\(reviewers)."
    }

    private func open(_ url: URL) {
        statusMenu.cancelTracking()
        NSWorkspace.shared.open(url)
    }

    private var accountLabel: String {
        if let login = monitoredAccountLogin {
            return "@\(login)"
        }
        return "GitHub CLI"
    }

    private var monitoredAccountLogin: String? {
        if case let .connected(login, _) = appModel.state.accountConnection {
            return login
        }
        return nil
    }

    private var updatedLabel: String {
        if appModel.state.isRefreshing { return "Refreshing…" }
        guard let lastUpdatedAt = appModel.state.lastUpdatedAt else { return "Ready" }
        return "Updated \(lastUpdatedAt.formatted(.relative(presentation: .named)))"
    }

    private func selectRepositoryScope(_ scope: RepositoryScope) {
        guard scope != appModel.state.repositoryScope else { return }
        pendingRepositoryScope = scope
        appModel.send(.selectRepositoryScope(scope))
    }

    @objc private func openURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(url)
    }

    @objc private func refresh() {
        appModel.send(.manualRefresh)
    }

    @objc private func openSettings() {
        actions.openSettings()
    }

    @objc private func openAbout() {
        actions.openAbout()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private static let menuWidth: CGFloat = 560
    private static let pullRequestRowHeight: CGFloat = 25
    private static let pullRequestLimit = 5
}

extension StatusItemController {
    func updateStatusMenu(for state: AppPresentationState) {
        guard let pendingRepositoryScope,
              pendingRepositoryScope == state.repositoryScope,
              isStatusMenuOpen else {
            rebuildStatusMenu()
            return
        }
        self.pendingRepositoryScope = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isStatusMenuOpen else { return }
            self.populateStatusMenu()
        }
    }
}

private enum StatusMenuSection {
    case needsYourReview
    case authored(AuthoredPullRequestSection)
    case legacyMyPRs

    var title: String {
        switch self {
        case .needsYourReview: "Needs your review"
        case .authored(.returnedToYou): "Returned to you"
        case .authored(.needsReviewers): "Needs reviewers"
        case .authored(.waitingForReviewers): "Waiting for reviewers"
        case .authored(.approved): "Approved"
        case .authored(.drafts): "Drafts"
        case .legacyMyPRs: "My PRs"
        }
    }

    var searchQualifiers: [String] {
        switch self {
        case .needsYourReview: ["review-requested:@me", "-is:draft"]
        case .authored(.returnedToYou): ["author:@me", "review:changes_requested", "-is:draft"]
        case .authored(.needsReviewers): ["author:@me", "review:none", "-is:draft"]
        case .authored(.waitingForReviewers): ["author:@me", "review:required", "-is:draft"]
        case .authored(.approved): ["author:@me", "review:approved", "-is:draft"]
        case .authored(.drafts): ["author:@me", "is:draft"]
        case .legacyMyPRs: ["author:@me"]
        }
    }
}

@MainActor
private protocol StatusMenuHighlighting: AnyObject {
    func setHighlighted(_ highlighted: Bool)
}

@MainActor
private final class StatusMenuHighlightState: ObservableObject {
    @Published var isHighlighted = false
}

@MainActor
private final class StatusMenuRowHostingView<Content: View>: NSHostingView<Content>, StatusMenuHighlighting {
    private let highlightState: StatusMenuHighlightState
    private let rowAccessibilityLabel: String
    private let onClick: () -> Void

    init(
        rootView: Content,
        highlightState: StatusMenuHighlightState,
        accessibilityLabel: String,
        onClick: @escaping () -> Void
    ) {
        self.highlightState = highlightState
        rowAccessibilityLabel = accessibilityLabel
        self.onClick = onClick
        super.init(rootView: rootView)
    }

    required init(rootView: Content) {
        highlightState = StatusMenuHighlightState()
        rowAccessibilityLabel = "Pull request"
        onClick = {}
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        guard event.type == .leftMouseUp else {
            super.mouseUp(with: event)
            return
        }
        onClick()
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityLabel() -> String? {
        rowAccessibilityLabel
    }

    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }

    func setHighlighted(_ highlighted: Bool) {
        highlightState.isHighlighted = highlighted
    }
}

private struct StatusMenuPullRequestRow: View {
    let pullRequest: PullRequestPresentation
    @ObservedObject var highlightState: StatusMenuHighlightState

    var body: some View {
        HStack(spacing: 7) {
            StatusMenuAuthorAvatar(author: pullRequest.author)
            Text("#\(String(pullRequest.number)): \(pullRequest.title)")
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if !pullRequest.reviewers.isEmpty {
                ReviewerRosterView(reviewers: pullRequest.reviewers)
            }
        }
        .padding(.horizontal, 7)
        .foregroundStyle(highlightState.isHighlighted ? Color.white : Color.primary)
        .background {
            if highlightState.isHighlighted {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .environment(\.colorScheme, .dark)
    }
}

private struct StatusMenuAuthorAvatar: View {
    let author: PullRequestAuthorPresentation?

    var body: some View {
        IdentityAvatarImage(
            displayName: author?.displayName,
            avatarURL: author?.avatarURL
        )
        .frame(width: 16, height: 16)
        .clipShape(Circle())
        .overlay { Circle().stroke(.black.opacity(0.45), lineWidth: 1) }
        .help(author.map { "Author: \($0.displayName)" } ?? "Author unavailable")
        .accessibilityHidden(true)
    }
}

private struct StatusMenuRepositoryFilter: View {
    let selection: RepositoryScope
    let pinnedCount: Int
    let onSelect: (RepositoryScope) -> Void
    let onManage: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                filterButton("All", filter: .all)
                filterButton("Pinned \(pinnedCount)", filter: .pinned)
            }
            .padding(3)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))

            Spacer()

            Button(action: onManage) {
                Label("Manage pins", systemImage: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Manage pinned repositories in Settings")
        }
        .padding(.horizontal, 11)
        .environment(\.colorScheme, .dark)
    }

    private func filterButton(_ title: String, filter: RepositoryScope) -> some View {
        Button {
            onSelect(filter)
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selection == filter ? Color.primary : Color.secondary)
                .frame(minWidth: 78)
                .padding(.vertical, 5)
                .background {
                    if selection == filter {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .selectedControlColor).opacity(0.75))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
