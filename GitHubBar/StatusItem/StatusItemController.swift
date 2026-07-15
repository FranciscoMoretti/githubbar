import AppKit
import GitHubBarCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let appModel: AppModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(appModel: AppModel) {
        self.appModel = appModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        apply(appModel.state)

        appModel.onStateChange = { [weak self] state in
            self?.apply(state)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = NSSize(width: 364, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(appModel: appModel)
        )
    }

    private func apply(_ state: AppPresentationState) {
        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.image(reviewCount: state.reviewCount)
        button.setAccessibilityTitle("GitHubBar. \(state.reviewCountAccessibilityLabel).")
        button.toolTip = "GitHubBar — \(state.reviewCountAccessibilityLabel)"
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            appModel.send(.setPopoverOpen(false))
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            appModel.send(.setPopoverOpen(true))
        }
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        appModel.send(.setPopoverOpen(true))
    }
}
