import AppKit
import GitHubBarCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appModel: AppModel?
    private var statusItemController: StatusItemController?
    private var visualValidationWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = WorkloadEngine(
            accountConnection: GitHubCLIAccountConnection(
                executableLocator: GitHubCLIExecutableLocator(),
                commandRunner: ProcessCommandRunner()
            ),
            workloadClient: GraphQLGitHubWorkloadClient(),
            snapshotStore: FileSnapshotStore(),
            settingsStore: UserDefaultsSettingsStore()
        )
        let model = AppModel(engine: engine)
        let statusItemController = StatusItemController(appModel: model)

        appModel = model
        self.statusItemController = statusItemController

        model.start()
        model.send(.launch)

        if ProcessInfo.processInfo.environment["GITHUBBAR_OPEN_POPOVER"] == "1" {
            DispatchQueue.main.async {
                statusItemController.showPopover()
            }
        }

        if ProcessInfo.processInfo.environment["GITHUBBAR_VISUAL_VALIDATION"] == "1" {
            showVisualValidationWindow(appModel: model)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.stop()
    }

    private func showVisualValidationWindow(appModel: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 364, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GitHubBar Visual Validation"
        window.contentView = NSHostingView(rootView: PopoverView(appModel: appModel))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        visualValidationWindow = window
    }
}
