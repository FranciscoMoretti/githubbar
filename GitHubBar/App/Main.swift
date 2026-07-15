import AppKit

@main
enum GitHubBarMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        let isVisualValidation = ProcessInfo.processInfo.environment["GITHUBBAR_VISUAL_VALIDATION"] == "1"
        application.setActivationPolicy(isVisualValidation ? .regular : .accessory)
        application.run()
        withExtendedLifetime(appDelegate) {}
    }
}
