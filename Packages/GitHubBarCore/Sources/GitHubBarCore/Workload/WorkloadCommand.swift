import Foundation

public enum WorkloadCommand: Equatable, Sendable {
    case launch
    case manualRefresh
    case setWorkloadSurfaceOpen(Bool)
    case confirmAccount(String)
    case requestAccountSelection
    case recheckAccountConnection
    case selectRepositoryScope(RepositoryScope)
    case setRefreshCadence(RefreshCadence)
    case setLaunchAtLogin(Bool)
}

public extension RefreshCadence {
    var displayName: String {
        switch self {
        case .adaptive: "Adaptive"
        case .manual: "Manual only"
        case .oneMinute: "Every minute"
        case .twoMinutes: "Every 2 minutes"
        case .fiveMinutes: "Every 5 minutes"
        case .fifteenMinutes: "Every 15 minutes"
        case .thirtyMinutes: "Every 30 minutes"
        }
    }
}

public enum RefreshCadence: Int, Codable, CaseIterable, Equatable, Sendable {
    case adaptive = -1
    case manual = 0
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
}
