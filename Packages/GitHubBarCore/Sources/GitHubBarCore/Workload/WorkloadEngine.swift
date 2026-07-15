import Foundation

public actor WorkloadEngine {
    private var state: AppPresentationState
    private var subscribers: [UUID: AsyncStream<AppPresentationState>.Continuation] = [:]

    public init(initialState: AppPresentationState = .empty) {
        state = initialState
    }

    public func states() -> AsyncStream<AppPresentationState> {
        let subscriberID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: AppPresentationState.self)
        subscribers[subscriberID] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(subscriberID) }
        }
        return stream
    }

    public func send(_ command: WorkloadCommand) async {
        switch command {
        case let .selectRepositoryScope(scope):
            guard state.repositoryScope != scope else { return }
            state.repositoryScope = scope
            publish()
        case .launch,
             .manualRefresh,
             .setPopoverOpen,
             .confirmAccount,
             .recheckAccountConnection,
             .setRefreshCadence:
            break
        }
    }

    private func publish() {
        for continuation in subscribers.values {
            continuation.yield(state)
        }
    }

    private func removeSubscriber(_ subscriberID: UUID) {
        subscribers.removeValue(forKey: subscriberID)
    }
}
