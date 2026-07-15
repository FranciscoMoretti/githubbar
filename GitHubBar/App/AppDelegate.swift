import AppKit
import GitHubBarCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appModel: AppModel?
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var applicationMenuController: ApplicationMenuController?
    private var visualValidationWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let workloadClient: any GitHubWorkloadClient = ProcessInfo.processInfo.environment["GITHUBBAR_FAILURE_DEMO"] == "1"
            ? UnavailableGitHubWorkloadClient()
            : GraphQLGitHubWorkloadClient()
        let engine = WorkloadEngine(
            accountConnection: GitHubCLIAccountConnection(
                executableLocator: GitHubCLIExecutableLocator(),
                commandRunner: ProcessCommandRunner()
            ),
            workloadClient: workloadClient,
            snapshotStore: FileSnapshotStore(),
            settingsStore: UserDefaultsSettingsStore(),
            diagnostics: OSLogReconciliationDiagnostics(),
            launchAtLoginController: MacLaunchAtLoginController()
        )
        let model = AppModel(engine: engine)
        let settingsWindowController = SettingsWindowController(
            appModel: model,
            updateController: DisabledUpdateController()
        )
        let actions = AppActions(
            openSettings: { [weak settingsWindowController] in settingsWindowController?.show() },
            openAbout: { [weak settingsWindowController] in settingsWindowController?.showAbout() }
        )
        let statusItemController = StatusItemController(appModel: model, actions: actions)
        let applicationMenuController = ApplicationMenuController(appModel: model, actions: actions)
        applicationMenuController.install()

        appModel = model
        self.statusItemController = statusItemController
        self.settingsWindowController = settingsWindowController
        self.applicationMenuController = applicationMenuController

        model.start()
        model.send(.launch)

        if ProcessInfo.processInfo.environment["GITHUBBAR_OPEN_POPOVER"] == "1" {
            DispatchQueue.main.async {
                statusItemController.showPopover()
            }
        }

        if ProcessInfo.processInfo.environment["GITHUBBAR_VISUAL_VALIDATION"] == "1" {
            showVisualValidationWindow(appModel: model, actions: actions)
        }
        if ProcessInfo.processInfo.environment["GITHUBBAR_OPEN_SETTINGS"] == "1" {
            DispatchQueue.main.async {
                settingsWindowController.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.stop()
    }

    private func showVisualValidationWindow(appModel: AppModel, actions: AppActions) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 364, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GitHubBar Visual Validation"
        window.contentView = NSHostingView(rootView: PopoverView(appModel: appModel, actions: actions))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        visualValidationWindow = window
    }
}
