import Foundation

public enum WorkloadCommand: Equatable, Sendable {
    case launch
    case manualRefresh
    case setPopoverOpen(Bool)
    case confirmAccount(String)
    case recheckAccountConnection
    case selectRepositoryScope(RepositoryScope)
    case setRefreshCadence(RefreshCadence)
}

public enum RefreshCadence: Int, Codable, CaseIterable, Equatable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
}
