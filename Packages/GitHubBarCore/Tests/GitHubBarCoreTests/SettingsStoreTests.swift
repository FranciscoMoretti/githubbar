import Foundation
import XCTest
@testable import GitHubBarCore

final class SettingsStoreTests: XCTestCase {
    func testPinnedRepositoriesPersistInUserDefaults() async {
        let suiteName = "GitHubBarCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let expected = AppSettings(
            selectedLogin: "FranciscoMoretti",
            pinnedRepositories: [
                PinnedRepository(id: "REPO-1", nameWithOwner: "owner/one"),
                PinnedRepository(id: "REPO-2", nameWithOwner: "owner/two"),
            ]
        )

        await store.save(expected)

        XCTAssertEqual(await store.load(), expected)
    }
}
