import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var selectedLogin: String?
    public var pinnedRepositories: Set<PinnedRepository>
    public var refreshCadence: RefreshCadence
    public var launchAtLogin: Bool

    public init(
        selectedLogin: String? = nil,
        pinnedRepositories: Set<PinnedRepository> = [],
        refreshCadence: RefreshCadence = .fiveMinutes,
        launchAtLogin: Bool = false
    ) {
        self.selectedLogin = selectedLogin
        self.pinnedRepositories = pinnedRepositories
        self.refreshCadence = refreshCadence
        self.launchAtLogin = launchAtLogin
    }

    private enum CodingKeys: String, CodingKey {
        case selectedLogin, repositoryScope, pinnedRepositoryIDs, pinnedRepositories, refreshCadence, launchAtLogin
    }

    private enum LegacyRepositoryScope: Codable {
        case all
        case selected(Set<String>)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedLogin = try container.decodeIfPresent(String.self, forKey: .selectedLogin)
        if let repositories = try container.decodeIfPresent(Set<PinnedRepository>.self, forKey: .pinnedRepositories) {
            pinnedRepositories = repositories
        } else {
            let explicitIDs = try container.decodeIfPresent(Set<String>.self, forKey: .pinnedRepositoryIDs)
            let legacyScope = try container.decodeIfPresent(LegacyRepositoryScope.self, forKey: .repositoryScope)
            let migratedIDs: Set<String> = explicitIDs ?? {
                guard case let .selected(repositoryIDs)? = legacyScope else { return [] }
                return repositoryIDs
            }()
            pinnedRepositories = Set(migratedIDs.map {
                PinnedRepository(id: $0, nameWithOwner: $0)
            })
        }
        refreshCadence = try container.decodeIfPresent(RefreshCadence.self, forKey: .refreshCadence) ?? .fiveMinutes
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(selectedLogin, forKey: .selectedLogin)
        try container.encode(pinnedRepositories, forKey: .pinnedRepositories)
        try container.encode(refreshCadence, forKey: .refreshCadence)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
    }
}

public protocol SettingsStore: Sendable {
    func load() async -> AppSettings
    func save(_ settings: AppSettings) async
}

public actor InMemorySettingsStore: SettingsStore {
    private var settings: AppSettings

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    public func load() async -> AppSettings { settings }

    public func save(_ settings: AppSettings) async {
        self.settings = settings
    }
}

public actor UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "githubbar.settings.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public func save(_ settings: AppSettings) async {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
