import Foundation

public protocol RefreshClock: Sendable {
    func now() async -> Date
    func sleep(for duration: Duration) async throws
}

public struct SystemRefreshClock: RefreshClock {
    public init() {}

    public func now() async -> Date { Date() }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

public enum AdaptiveRefreshReason: String, Equatable, Sendable {
    case constrained
    case recentInteraction
    case warm
    case idle
    case longIdle
}

public struct AdaptiveRefreshDecision: Equatable, Sendable {
    public let delay: Duration
    public let reason: AdaptiveRefreshReason

    public init(delay: Duration, reason: AdaptiveRefreshReason) {
        self.delay = delay
        self.reason = reason
    }
}

public enum AdaptiveRefreshPolicy {
    public static func decision(
        now: Date,
        lastWorkloadSurfaceOpenAt: Date?,
        isConstrained: Bool = false
    ) -> AdaptiveRefreshDecision {
        if isConstrained {
            return AdaptiveRefreshDecision(delay: .minutes(30), reason: .constrained)
        }
        guard let lastWorkloadSurfaceOpenAt else {
            return AdaptiveRefreshDecision(delay: .minutes(30), reason: .longIdle)
        }

        let age = max(0, now.timeIntervalSince(lastWorkloadSurfaceOpenAt))
        if age <= 5 * 60 {
            return AdaptiveRefreshDecision(delay: .minutes(2), reason: .recentInteraction)
        }
        if age <= 60 * 60 {
            return AdaptiveRefreshDecision(delay: .minutes(5), reason: .warm)
        }
        if age < 4 * 60 * 60 {
            return AdaptiveRefreshDecision(delay: .minutes(15), reason: .idle)
        }
        return AdaptiveRefreshDecision(delay: .minutes(30), reason: .longIdle)
    }
}

extension Duration {
    static func minutes(_ minutes: Int) -> Duration {
        .seconds(minutes * 60)
    }

    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
