import Foundation

public actor WorkloadEngine {
    private var state: AppPresentationState
    private var subscribers: [UUID: AsyncStream<AppPresentationState>.Continuation] = [:]
    private let accountConnection: any AccountConnection
    private let workloadClient: any GitHubWorkloadClient
    private let snapshotStore: any SnapshotStore
    private let settingsStore: any SettingsStore
    private var settings: AppSettings?
    private var resolvedAccount: ResolvedAccount?
    private var currentSnapshot: WorkloadSnapshot?

    public init(
        initialState: AppPresentationState = .empty,
        accountConnection: any AccountConnection = UnavailableAccountConnection(),
        workloadClient: any GitHubWorkloadClient = UnavailableGitHubWorkloadClient(),
        snapshotStore: any SnapshotStore = InMemorySnapshotStore(),
        settingsStore: any SettingsStore = InMemorySettingsStore()
    ) {
        state = initialState
        self.accountConnection = accountConnection
        self.workloadClient = workloadClient
        self.snapshotStore = snapshotStore
        self.settingsStore = settingsStore
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
        case .launch:
            let loadedSettings = await settingsStore.load()
            settings = loadedSettings
            state.repositoryScope = loadedSettings.repositoryScope
            if let selectedLogin = loadedSettings.selectedLogin {
                await restoreSnapshot(hostname: "github.com", accountLogin: selectedLogin)
            }
            await inspectAccount(selectedLogin: loadedSettings.selectedLogin)
        case .recheckAccountConnection:
            let currentSettings = await currentSettings()
            await inspectAccount(selectedLogin: currentSettings.selectedLogin)
        case let .confirmAccount(login):
            var currentSettings = await currentSettings()
            if currentSettings.selectedLogin?.caseInsensitiveCompare(login) != .orderedSame {
                clearAccountDerivedPresentation()
            }
            currentSettings.selectedLogin = login
            settings = currentSettings
            await settingsStore.save(currentSettings)
            await inspectAccount(selectedLogin: login)
        case let .selectRepositoryScope(scope):
            guard state.repositoryScope != scope else { return }
            state.repositoryScope = scope
            var currentSettings = await currentSettings()
            currentSettings.repositoryScope = scope
            settings = currentSettings
            await settingsStore.save(currentSettings)
            publish()
            await reconcile()
        case let .setRefreshCadence(cadence):
            var currentSettings = await currentSettings()
            currentSettings.refreshCadence = cadence
            settings = currentSettings
            await settingsStore.save(currentSettings)
        case .manualRefresh:
            await reconcile()
        case .setPopoverOpen:
            break
        }
    }

    private func currentSettings() async -> AppSettings {
        if let settings { return settings }
        let loadedSettings = await settingsStore.load()
        settings = loadedSettings
        return loadedSettings
    }

    private func inspectAccount(selectedLogin: String?) async {
        resolvedAccount = nil
        state.accountConnection = .checking
        publish()

        switch await accountConnection.inspect(selectedLogin: selectedLogin) {
        case .cliMissing:
            state.accountConnection = .connectionRequired(.cliMissing)
        case .authenticationRequired:
            state.accountConnection = .connectionRequired(.authenticationRequired)
        case let .selectionRequired(candidates):
            state.accountConnection = .selectionRequired(candidates)
        case let .connected(account):
            resolvedAccount = account
            var currentSettings = await currentSettings()
            if currentSettings.selectedLogin?.caseInsensitiveCompare(account.login) != .orderedSame {
                currentSettings.selectedLogin = account.login
                settings = currentSettings
                await settingsStore.save(currentSettings)
            }
            state.accountConnection = .connected(login: account.login, accessCoverage: account.accessCoverage)
            publish()
            await reconcile()
            return
        case .failed:
            state.accountConnection = .connectionRequired(.unavailable)
        }
        publish()
    }

    private func reconcile() async {
        guard let account = resolvedAccount else { return }
        state.isRefreshing = true
        publish()

        switch await workloadClient.reconcile(
            account: account,
            repositoryScope: state.repositoryScope,
            previousSnapshot: currentSnapshot
        ) {
        case let .complete(snapshot, _):
            apply(snapshot)
            state.refreshHealth = .fresh
            try? await snapshotStore.save(snapshot)
        case let .partial(snapshot, metadata):
            apply(snapshot)
            state.refreshHealth = .partial(
                message: metadata.warnings.first ?? "Some pull-request data could not be refreshed."
            )
        case let .failed(failure, _):
            state.refreshHealth = failure == .rateLimited
                ? .rateLimited(until: nil)
                : .failed(message: "GitHub could not refresh the active workload.")
        }
        state.isRefreshing = false
        publish()
    }

    private func apply(_ snapshot: WorkloadSnapshot) {
        currentSnapshot = snapshot
        state.availableRepositories = snapshot.availableRepositories
        state.waitingForReview = snapshot.waitingForReview
        state.authoredPullRequests = snapshot.authoredPullRequests
        state.lastUpdatedAt = snapshot.capturedAt
    }

    private func restoreSnapshot(hostname: String, accountLogin: String) async {
        guard let snapshot = try? await snapshotStore.load(hostname: hostname, accountLogin: accountLogin),
              snapshot.repositoryScope == state.repositoryScope else {
            return
        }
        apply(snapshot)
        state.refreshHealth = .cached
        publish()
    }

    private func clearAccountDerivedPresentation() {
        resolvedAccount = nil
        currentSnapshot = nil
        state.availableRepositories = []
        state.waitingForReview = []
        state.authoredPullRequests = []
        state.lastUpdatedAt = nil
        state.refreshHealth = .idle
        state.isRefreshing = false
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
