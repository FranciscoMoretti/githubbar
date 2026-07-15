import Foundation
import XCTest
@testable import GitHubBarCore

final class SnapshotStoreTests: XCTestCase {
    func testSnapshotRoundTripIsOwnerOnlyAndAccountBound() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubbar-snapshot-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directoryURL: directory)
        let snapshot = fixtureSnapshot()

        try await store.save(snapshot)

        XCTAssertEqual(
            try await store.load(hostname: "github.com", accountLogin: "FranciscoMoretti"),
            snapshot
        )
        XCTAssertNil(try await store.load(hostname: "github.com", accountLogin: "someone-else"))
        let fileURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first
        )
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testCorruptSnapshotIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubbar-corrupt-snapshot-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directoryURL: directory)
        try await store.save(fixtureSnapshot())
        let fileURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first
        )
        try Data("not-json".utf8).write(to: fileURL, options: .atomic)

        do {
            _ = try await store.load(hostname: "github.com", accountLogin: "FranciscoMoretti")
            XCTFail("Expected corrupt Snapshot rejection")
        } catch SnapshotStoreError.corrupt {
            // Expected.
        }
    }

    private func fixtureSnapshot() -> WorkloadSnapshot {
        WorkloadSnapshot(
            hostname: "github.com",
            accountLogin: "FranciscoMoretti",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completeness: .complete,
            repositoryScope: .all,
            availableRepositories: [],
            waitingForReview: [],
            authoredPullRequests: []
        )
    }
}
