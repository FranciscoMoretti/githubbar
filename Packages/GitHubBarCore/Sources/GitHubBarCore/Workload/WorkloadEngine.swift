import Foundation

public actor WorkloadEngine {
    private var state: AppPresentationState
    private var subscribers: [UUID: AsyncStream<AppPresentationState>.Continuation] = [:]
    private let accountConnection: any AccountConnection
    private let workloadClient: any GitHubWorkloadClient
    private let snapshotStore: any SnapshotStore
    private let settingsStore: any SettingsStore
    private let clock: any RefreshClock
    private let diagnostics: any ReconciliationDiagnostics
    private let launchAtLoginController: any LaunchAtLoginControlling

    private var settings: AppSettings?
    private var resolvedAccount: ResolvedAccount?
    private var currentSnapshot: WorkloadSnapshot?
    private var generation = 0
    private var activeReconciliationGeneration: Int?
    private var isReconciling = false
    private var queuedTrigger: ReconciliationTrigger?

    private var refreshTimerTask: Task<Void, Never>?
    private var scheduledRefreshAt: Date?
    private var popoverRefreshTask: Task<Void, Never>?
    private var rateLimitRetryTask: Task<Void, Never>?
    private var rateLimitAttempt = 0
    private var isPopoverOpen = false
    private var lastPopoverOpenAt: Date?

    private static let popoverOpenDebounce = Duration.milliseconds(1_200)
    private static let maximumRateLimitAttempts = 3

    public init(
        initialState: AppPresentationState = .empty,
        accountConnection: any AccountConnection = UnavailableAccountConnection(),
        workloadClient: any GitHubWorkloadClient = UnavailableGitHubWorkloadClient(),
        snapshotStore: any SnapshotStore = InMemorySnapshotStore(),
        settingsStore: any SettingsStore = InMemorySettingsStore(),
        clock: any RefreshClock = SystemRefreshClock(),
        diagnostics: any ReconciliationDiagnostics = NoopReconciliationDiagnostics(),
        launchAtLoginController: any LaunchAtLoginControlling = UnavailableLaunchAtLoginController()
    ) {
        state = initialState
        self.accountConnection = accountConnection
        self.workloadClient = workloadClient
        self.snapshotStore = snapshotStore
        self.settingsStore = settingsStore
        self.clock = clock
        self.diagnostics = diagnostics
        self.launchAtLoginController = launchAtLoginController
    }

    deinit {
        refreshTimerTask?.cancel()
        popoverRefreshTask?.cancel()
        rateLimitRetryTask?.cancel()
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
            state.refreshCadence = loadedSettings.refreshCadence
            state.launchAtLoginRequested = loadedSettings.launchAtLogin
            state.launchAtLoginStatus = await launchAtLoginController.status()
            if let selectedLogin = loadedSettings.selectedLogin {
                await restoreSnapshot(hostname: "github.com", accountLogin: selectedLogin)
            }
            await inspectAccount(selectedLogin: loadedSettings.selectedLogin, trigger: .launch)
            await restartRefreshTimer()
        case .recheckAccountConnection:
            let currentSettings = await currentSettings()
            await inspectAccount(selectedLogin: currentSettings.selectedLogin, trigger: .accountChanged)
            await restartRefreshTimer()
        case let .confirmAccount(login):
            var currentSettings = await currentSettings()
            if currentSettings.selectedLogin?.caseInsensitiveCompare(login) != .orderedSame {
                invalidatePublication(clearPresentation: true)
            }
            currentSettings.selectedLogin = login
            settings = currentSettings
            await settingsStore.save(currentSettings)
            await inspectAccount(selectedLogin: login, trigger: .accountChanged)
            await restartRefreshTimer()
        case .requestAccountSelection:
            invalidatePublication(clearPresentation: true)
            var currentSettings = await currentSettings()
            currentSettings.selectedLogin = nil
            settings = currentSettings
            await settingsStore.save(currentSettings)
            await inspectAccount(selectedLogin: nil, trigger: .accountChanged)
            await restartRefreshTimer()
        case let .selectRepositoryScope(scope):
            guard state.repositoryScope != scope else { return }
            invalidatePublication(clearPresentation: false)
            state.repositoryScope = scope
            var currentSettings = await currentSettings()
            currentSettings.repositoryScope = scope
            settings = currentSettings
            await settingsStore.save(currentSettings)
            publish()
            await requestReconciliation(trigger: .scopeChanged)
        case let .setRefreshCadence(cadence):
            var currentSettings = await currentSettings()
            currentSettings.refreshCadence = cadence
            settings = currentSettings
            state.refreshCadence = cadence
            await settingsStore.save(currentSettings)
            publish()
            await restartRefreshTimer()
        case let .setLaunchAtLogin(isEnabled):
            let status = await launchAtLoginController.setEnabled(isEnabled)
            state.launchAtLoginStatus = status
            switch status {
            case .enabled, .disabled, .requiresApproval:
                var currentSettings = await currentSettings()
                currentSettings.launchAtLogin = isEnabled
                settings = currentSettings
                state.launchAtLoginRequested = isEnabled
                await settingsStore.save(currentSettings)
            case .failed, .unavailable:
                break
            }
            publish()
        case .manualRefresh:
            rateLimitRetryTask?.cancel()
            rateLimitRetryTask = nil
            rateLimitAttempt = 0
            await requestReconciliation(trigger: .manual)
        case let .setPopoverOpen(isOpen):
            await setPopoverOpen(isOpen)
        }
    }

    private func currentSettings() async -> AppSettings {
        if let settings { return settings }
        let loadedSettings = await settingsStore.load()
        settings = loadedSettings
        return loadedSettings
    }

    private func inspectAccount(selectedLogin: String?, trigger: ReconciliationTrigger) async {
        invalidatePublication(clearPresentation: false)
        let inspectionGeneration = generation
        resolvedAccount = nil
        state.isRefreshing = false
        state.accountConnection = .checking
        publish()

        let result = await accountConnection.inspect(selectedLogin: selectedLogin)
        guard generation == inspectionGeneration else { return }
        switch result {
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
            await requestReconciliation(trigger: trigger)
            return
        case .failed:
            state.accountConnection = .connectionRequired(.unavailable)
        }
        publish()
    }

    private func requestReconciliation(trigger: ReconciliationTrigger) async {
        guard resolvedAccount != nil else { return }
        if isReconciling {
            if activeReconciliationGeneration != generation {
                queuedTrigger = trigger
            }
            return
        }

        isReconciling = true
        var nextTrigger: ReconciliationTrigger? = trigger
        while let triggerToRun = nextTrigger {
            queuedTrigger = nil
            activeReconciliationGeneration = generation
            await performReconciliation(trigger: triggerToRun)
            nextTrigger = queuedTrigger
        }
        activeReconciliationGeneration = nil
        isReconciling = false
        if state.isRefreshing {
            state.isRefreshing = false
            publish()
        }
    }

    private func performReconciliation(trigger: ReconciliationTrigger) async {
        guard let account = resolvedAccount else { return }
        let reconciliationGeneration = generation
        let scope = state.repositoryScope
        let previousSnapshot = currentSnapshot
        let start = ContinuousClock.now
        state.isRefreshing = true
        publish()

        let result = await workloadClient.reconcile(
            account: account,
            repositoryScope: scope,
            previousSnapshot: previousSnapshot
        )
        let duration = start.duration(to: .now)
        guard reconciliationGeneration == generation else { return }

        let diagnostic: ReconciliationDiagnostic
        switch result {
        case let .complete(snapshot, metadata):
            rateLimitRetryTask?.cancel()
            rateLimitRetryTask = nil
            rateLimitAttempt = 0
            apply(snapshot)
            state.refreshHealth = .fresh
            try? await snapshotStore.save(snapshot)
            diagnostic = ReconciliationDiagnostic(
                trigger: trigger,
                duration: duration,
                completeness: .complete,
                failure: nil,
                queryCost: metadata.queryCost,
                waitingCount: snapshot.waitingForReview.count,
                authoredCount: snapshot.authoredPullRequests.count
            )
        case let .partial(snapshot, metadata):
            rateLimitRetryTask?.cancel()
            rateLimitRetryTask = nil
            rateLimitAttempt = 0
            let merged = snapshot.mergingConfirmedUpdates(into: previousSnapshot)
            apply(merged)
            state.refreshHealth = .partial(
                message: metadata.warnings.first ?? "Some pull-request data could not be refreshed."
            )
            diagnostic = ReconciliationDiagnostic(
                trigger: trigger,
                duration: duration,
                completeness: .partial,
                failure: nil,
                queryCost: metadata.queryCost,
                waitingCount: merged.waitingForReview.count,
                authoredCount: merged.authoredPullRequests.count
            )
        case let .failed(failure, metadata):
            if failure == .rateLimited {
                state.refreshHealth = .rateLimited(until: metadata.resetAt)
                rateLimitAttempt += 1
                scheduleRateLimitRetry(after: metadata, generation: reconciliationGeneration)
            } else {
                rateLimitAttempt = 0
                state.refreshHealth = .failed(message: "GitHub could not refresh the active workload.")
            }
            diagnostic = ReconciliationDiagnostic(
                trigger: trigger,
                duration: duration,
                completeness: nil,
                failure: failure,
                queryCost: metadata.queryCost,
                waitingCount: state.waitingForReview.count,
                authoredCount: state.authoredPullRequests.count
            )
        }
        state.isRefreshing = false
        publish()
        await diagnostics.record(diagnostic)
    }

    private func setPopoverOpen(_ isOpen: Bool) async {
        isPopoverOpen = isOpen
        popoverRefreshTask?.cancel()
        popoverRefreshTask = nil
        guard isOpen else { return }

        let now = await clock.now()
        lastPopoverOpenAt = now
        await advanceAdaptiveTimerIfNeeded(now: now)
        let expectedGeneration = generation
        let clock = self.clock
        popoverRefreshTask = Task { [weak self] in
            do {
                try await clock.sleep(for: Self.popoverOpenDebounce)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.popoverDebounceElapsed(expectedGeneration: expectedGeneration)
        }
    }

    private func popoverDebounceElapsed(expectedGeneration: Int) async {
        popoverRefreshTask = nil
        guard isPopoverOpen, generation == expectedGeneration else { return }
        await requestReconciliation(trigger: .popoverOpen)
    }

    private func restartRefreshTimer() async {
        refreshTimerTask?.cancel()
        refreshTimerTask = nil
        scheduledRefreshAt = nil
        guard resolvedAccount != nil else { return }
        let cadence = await currentSettings().refreshCadence
        guard cadence != .manual else { return }
        let now = await clock.now()
        let delay = refreshDelay(for: cadence, now: now)
        scheduleRefreshTimer(at: now.addingTimeInterval(delay.timeInterval))
    }

    private func refreshDelay(for cadence: RefreshCadence, now: Date) -> Duration {
        if cadence == .adaptive {
            return AdaptiveRefreshPolicy.decision(now: now, lastPopoverOpenAt: lastPopoverOpenAt).delay
        }
        return .seconds(max(1, cadence.rawValue))
    }

    private func scheduleRefreshTimer(at deadline: Date) {
        refreshTimerTask?.cancel()
        scheduledRefreshAt = deadline
        let clock = self.clock
        refreshTimerTask = Task { [weak self] in
            let now = await clock.now()
            let delay = Duration.seconds(max(0, deadline.timeIntervalSince(now)))
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.refreshTimerFired(deadline: deadline)
        }
    }

    private func refreshTimerFired(deadline: Date) async {
        refreshTimerTask = nil
        scheduledRefreshAt = nil
        await requestReconciliation(trigger: .scheduled)
        guard resolvedAccount != nil else { return }
        let cadence = await currentSettings().refreshCadence
        guard cadence != .manual else { return }

        let now = await clock.now()
        if cadence == .adaptive {
            let delay = refreshDelay(for: cadence, now: now)
            scheduleRefreshTimer(at: now.addingTimeInterval(delay.timeInterval))
            return
        }

        let interval = TimeInterval(cadence.rawValue)
        var nextDeadline = deadline.addingTimeInterval(interval)
        while nextDeadline <= now {
            nextDeadline = nextDeadline.addingTimeInterval(interval)
        }
        scheduleRefreshTimer(at: nextDeadline)
    }

    private func advanceAdaptiveTimerIfNeeded(now: Date) async {
        guard await currentSettings().refreshCadence == .adaptive else { return }
        let candidate = now.addingTimeInterval(
            AdaptiveRefreshPolicy.decision(now: now, lastPopoverOpenAt: lastPopoverOpenAt).delay.timeInterval
        )
        if let scheduledRefreshAt, scheduledRefreshAt <= candidate { return }
        scheduleRefreshTimer(at: candidate)
    }

    private func scheduleRateLimitRetry(
        after metadata: ReconciliationMetadata,
        generation expectedGeneration: Int
    ) {
        guard rateLimitAttempt < Self.maximumRateLimitAttempts else { return }

        rateLimitRetryTask?.cancel()
        let clock = self.clock
        let attempt = rateLimitAttempt
        rateLimitRetryTask = Task { [weak self] in
            let now = await clock.now()
            let resetDelay = metadata.resetAt.map { max(0, $0.timeIntervalSince(now)) } ?? 0
            let exponentialDelay = pow(2.0, Double(attempt))
            let boundedDelay = min(30 * 60, max(exponentialDelay, resetDelay))
            do {
                try await clock.sleep(for: .seconds(boundedDelay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.rateLimitRetryFired(expectedGeneration: expectedGeneration)
        }
    }

    private func rateLimitRetryFired(expectedGeneration: Int) async {
        rateLimitRetryTask = nil
        guard generation == expectedGeneration else { return }
        await requestReconciliation(trigger: .rateLimitRetry)
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

    private func invalidatePublication(clearPresentation: Bool) {
        generation += 1
        queuedTrigger = nil
        rateLimitRetryTask?.cancel()
        rateLimitRetryTask = nil
        rateLimitAttempt = 0
        if clearPresentation {
            clearAccountDerivedPresentation()
        }
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
