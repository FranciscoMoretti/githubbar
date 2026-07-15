import Foundation
import GitHubBarCore
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var state: AppPresentationState

    @ObservationIgnored private let engine: WorkloadEngine
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored var onStateChange: ((AppPresentationState) -> Void)?

    init(engine: WorkloadEngine, initialState: AppPresentationState = .empty) {
        self.engine = engine
        state = initialState
    }

    func start() {
        guard stateTask == nil else { return }
        stateTask = Task { [weak self] in
            guard let self else { return }
            let states = await engine.states()
            for await state in states {
                guard !Task.isCancelled else { return }
                self.state = state
                onStateChange?(state)
            }
        }
    }

    func stop() {
        stateTask?.cancel()
        stateTask = nil
    }

    func send(_ command: WorkloadCommand) {
        Task { await engine.send(command) }
    }
}
