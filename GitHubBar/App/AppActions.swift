import AppKit

@MainActor
struct AppActions {
    let openSettings: () -> Void
    let openAbout: () -> Void

    init(
        openSettings: @escaping () -> Void = {},
        openAbout: @escaping () -> Void = { NSApp.orderFrontStandardAboutPanel(nil) }
    ) {
        self.openSettings = openSettings
        self.openAbout = openAbout
    }
}
