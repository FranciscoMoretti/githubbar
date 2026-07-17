import AppKit
import GitHubBarCore

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
            updateController: UpdateControllerFactory.make()
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

        if ProcessInfo.processInfo.environment["GITHUBBAR_OPEN_MENU"] == "1" {
            DispatchQueue.main.async {
                statusItemController.showMenu()
            }
        }

        if ProcessInfo.processInfo.environment["GITHUBBAR_VISUAL_VALIDATION"] == "1" {
            showVisualValidationWindow(
                statusItemController: statusItemController
            )
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

    private func showVisualValidationWindow(statusItemController: StatusItemController) {
        let height: CGFloat = 640
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 390,
                height: height
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GitHubBar Visual Validation"
        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let openMenuButton = NSButton(title: "Open GitHubBar menu", target: self, action: #selector(openMenuValidation))
        openMenuButton.frame = NSRect(x: 110, y: height / 2 - 16, width: 170, height: 32)
        background.addSubview(openMenuButton)
        window.contentView = background
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        visualValidationWindow = window
    }

    @objc private func openMenuValidation() {
        statusItemController?.showMenu()
    }
}
