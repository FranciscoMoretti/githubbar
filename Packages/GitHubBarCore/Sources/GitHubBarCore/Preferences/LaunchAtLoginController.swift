import Foundation

public enum LaunchAtLoginStatus: Codable, Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case failed(message: String)
    case unavailable(message: String)
}

public protocol LaunchAtLoginControlling: Sendable {
    func status() async -> LaunchAtLoginStatus
    func setEnabled(_ isEnabled: Bool) async -> LaunchAtLoginStatus
}

public struct UnavailableLaunchAtLoginController: LaunchAtLoginControlling {
    public init() {}

    public func status() async -> LaunchAtLoginStatus {
        .unavailable(message: "Launch at login is unavailable in this build.")
    }

    public func setEnabled(_ isEnabled: Bool) async -> LaunchAtLoginStatus {
        .unavailable(message: "Launch at login is unavailable in this build.")
    }
}
