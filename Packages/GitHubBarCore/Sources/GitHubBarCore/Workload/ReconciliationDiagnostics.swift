import Foundation
import OSLog

public enum ReconciliationTrigger: String, Sendable {
    case launch
    case manual
    case popoverOpen
    case scheduled
    case accountChanged
    case scopeChanged
    case rateLimitRetry
}

public struct ReconciliationDiagnostic: Sendable {
    public let trigger: ReconciliationTrigger
    public let duration: Duration
    public let completeness: WorkloadSnapshot.Completeness?
    public let failure: WorkloadFailure?
    public let queryCost: Int
    public let waitingCount: Int
    public let authoredCount: Int

    public init(
        trigger: ReconciliationTrigger,
        duration: Duration,
        completeness: WorkloadSnapshot.Completeness?,
        failure: WorkloadFailure?,
        queryCost: Int,
        waitingCount: Int,
        authoredCount: Int
    ) {
        self.trigger = trigger
        self.duration = duration
        self.completeness = completeness
        self.failure = failure
        self.queryCost = queryCost
        self.waitingCount = waitingCount
        self.authoredCount = authoredCount
    }
}

public protocol ReconciliationDiagnostics: Sendable {
    func record(_ diagnostic: ReconciliationDiagnostic) async
}

public struct NoopReconciliationDiagnostics: ReconciliationDiagnostics {
    public init() {}
    public func record(_ diagnostic: ReconciliationDiagnostic) async {}
}

public struct OSLogReconciliationDiagnostics: ReconciliationDiagnostics {
    private let logger = Logger(subsystem: "com.franciscomoretti.GitHubBar", category: "reconciliation")

    public init() {}

    public func record(_ diagnostic: ReconciliationDiagnostic) async {
        let milliseconds = diagnostic.duration.timeInterval * 1_000
        let completeness = diagnostic.completeness?.rawValue ?? "none"
        let failure = diagnostic.failure?.rawValue ?? "none"
        logger.info(
            "trigger=\(diagnostic.trigger.rawValue, privacy: .public) duration_ms=\(milliseconds, privacy: .public) completeness=\(completeness, privacy: .public) failure=\(failure, privacy: .public) query_cost=\(diagnostic.queryCost, privacy: .public) waiting=\(diagnostic.waitingCount, privacy: .public) authored=\(diagnostic.authoredCount, privacy: .public)"
        )
    }
}
