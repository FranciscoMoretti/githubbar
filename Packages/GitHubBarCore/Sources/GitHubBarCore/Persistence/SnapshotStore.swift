import Foundation

public protocol SnapshotStore: Sendable {
    func load(hostname: String, accountLogin: String) async throws -> WorkloadSnapshot?
    func save(_ snapshot: WorkloadSnapshot) async throws
    func clear(hostname: String, accountLogin: String) async throws
}

public enum SnapshotStoreError: Error, Sendable {
    case corrupt
    case incompatibleVersion
    case identityMismatch
}

public actor InMemorySnapshotStore: SnapshotStore {
    private var snapshot: WorkloadSnapshot?

    public init(snapshot: WorkloadSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load(hostname: String, accountLogin: String) async throws -> WorkloadSnapshot? {
        guard let snapshot else { return nil }
        guard snapshot.schemaVersion == 1 else { throw SnapshotStoreError.incompatibleVersion }
        guard snapshot.hostname.caseInsensitiveCompare(hostname) == .orderedSame,
              snapshot.accountLogin.caseInsensitiveCompare(accountLogin) == .orderedSame else {
            throw SnapshotStoreError.identityMismatch
        }
        return snapshot
    }

    public func save(_ snapshot: WorkloadSnapshot) async throws {
        self.snapshot = snapshot
    }

    public func clear(hostname: String, accountLogin: String) async throws {
        guard snapshot?.hostname.caseInsensitiveCompare(hostname) == .orderedSame,
              snapshot?.accountLogin.caseInsensitiveCompare(accountLogin) == .orderedSame else {
            return
        }
        snapshot = nil
    }
}

public actor FileSnapshotStore: SnapshotStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    public init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directoryURL = applicationSupport.appendingPathComponent("GitHubBar", isDirectory: true)
        }
    }

    public func load(hostname: String, accountLogin: String) async throws -> WorkloadSnapshot? {
        let fileURL = snapshotURL(hostname: hostname, accountLogin: accountLogin)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        guard let snapshot = try? decoder().decode(WorkloadSnapshot.self, from: data) else {
            throw SnapshotStoreError.corrupt
        }
        guard snapshot.schemaVersion == 1 else {
            throw SnapshotStoreError.incompatibleVersion
        }
        guard snapshot.hostname.caseInsensitiveCompare(hostname) == .orderedSame,
              snapshot.accountLogin.caseInsensitiveCompare(accountLogin) == .orderedSame else {
            throw SnapshotStoreError.identityMismatch
        }
        return snapshot
    }

    public func save(_ snapshot: WorkloadSnapshot) async throws {
        try ensureDirectory()
        let fileURL = snapshotURL(hostname: snapshot.hostname, accountLogin: snapshot.accountLogin)
        let data = try encoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func clear(hostname: String, accountLogin: String) async throws {
        let fileURL = snapshotURL(hostname: hostname, accountLogin: accountLogin)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }

    private func snapshotURL(hostname: String, accountLogin: String) -> URL {
        let identity = "\(safeComponent(hostname))--\(safeComponent(accountLogin))"
        return directoryURL.appendingPathComponent("\(identity).snapshot.json", isDirectory: false)
    }

    private func safeComponent(_ value: String) -> String {
        value.lowercased().map { character in
            character.isLetter || character.isNumber || character == "-" || character == "."
                ? String(character)
                : "_"
        }.joined()
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
