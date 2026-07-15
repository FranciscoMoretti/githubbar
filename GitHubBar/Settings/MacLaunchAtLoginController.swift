import Foundation
import GitHubBarCore
import ServiceManagement

final class MacLaunchAtLoginController: LaunchAtLoginControlling, @unchecked Sendable {
    func status() async -> LaunchAtLoginStatus {
        await MainActor.run { Self.map(SMAppService.mainApp.status) }
    }

    func setEnabled(_ isEnabled: Bool) async -> LaunchAtLoginStatus {
        await MainActor.run {
            do {
                if isEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return Self.map(SMAppService.mainApp.status)
            } catch {
                return .failed(
                    message: isEnabled
                        ? "GitHubBar could not be added to Login Items. Open System Settings and try again."
                        : "GitHubBar could not be removed from Login Items. Open System Settings and try again."
                )
            }
        }
    }

    @MainActor
    private static func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable(message: "This build cannot register as a Login Item.")
        @unknown default: .unavailable(message: "The Login Item status is unavailable.")
        }
    }
}
