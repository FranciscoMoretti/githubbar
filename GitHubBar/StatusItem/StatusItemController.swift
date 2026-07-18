import AppKit
import GitHubBarCore

@MainActor
final class StatusItemController: NSObject {
    let appModel: AppModel
    let actions: AppActions
    let statusItem: NSStatusItem
    let statusMenu = NSMenu()
    var isStatusMenuOpen = false
    var highlightedStatusMenuItem: NSMenuItem?
    var registeredShortcut: GitHubBarShortcut?

    init(appModel: AppModel, actions: AppActions = AppActions()) {
        self.appModel = appModel
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureStatusItem()
        apply(appModel.state)

        appModel.onStateChange = { [weak self] state in
            self?.apply(state)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        configureStatusMenu()
    }

    private func apply(_ state: AppPresentationState) {
        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.image(reviewCount: state.reviewCount)
        button.setAccessibilityTitle("GitHubBar. \(state.reviewCountAccessibilityLabel).")
        button.toolTip = "GitHubBar — \(state.reviewCountAccessibilityLabel)"
        rebuildStatusMenu()
    }

    func showMenu() {
        statusItem.button?.performClick(nil)
    }

    func toggleMenu() {
        if isStatusMenuOpen {
            statusMenu.cancelTracking()
        } else {
            showMenu()
        }
    }

    func setRegisteredShortcut(_ shortcut: GitHubBarShortcut) {
        registeredShortcut = shortcut
        rebuildStatusMenu()
    }
}
