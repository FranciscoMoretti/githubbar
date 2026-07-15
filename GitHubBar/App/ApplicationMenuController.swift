import AppKit
import GitHubBarCore

@MainActor
final class ApplicationMenuController: NSObject {
    private let appModel: AppModel
    private let actions: AppActions

    init(appModel: AppModel, actions: AppActions) {
        self.appModel = appModel
        self.actions = actions
        super.init()
    }

    func install() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "GitHubBar")

        applicationMenu.addItem(
            NSMenuItem(title: "About GitHubBar", action: #selector(showAbout), keyEquivalent: "")
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        )
        applicationMenu.addItem(
            NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            NSMenuItem(title: "Quit GitHubBar", action: #selector(quit), keyEquivalent: "q")
        )

        for item in applicationMenu.items {
            item.target = self
        }
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func refresh() {
        appModel.send(.manualRefresh)
    }

    @objc private func showSettings() {
        actions.openSettings()
    }

    @objc private func showAbout() {
        actions.openAbout()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
