import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let appModel: AppModel
    private let updateModel: UpdateModel
    private var window: NSWindow?

    init(appModel: AppModel, updateController: any UpdateControlling) {
        self.appModel = appModel
        updateModel = UpdateModel(controller: updateController)
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GitHubBar Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 620, height: 650)
        window.contentView = NSHostingView(
            rootView: SettingsView(appModel: appModel, updateModel: updateModel)
        )
        return window
    }
}
