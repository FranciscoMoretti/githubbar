import Foundation

public struct GitHubTransportResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data

    public init(statusCode: Int, headers: [String: String], data: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
    }
}

public protocol GitHubTransport: Sendable {
    func execute(body: Data, accessToken: GitHubAccessToken) async throws -> GitHubTransportResponse
}

public enum GitHubTransportError: Error, Sendable {
    case invalidResponse
    case http(statusCode: Int, retryAfter: TimeInterval?, rateLimitResetAt: Date?)
}

public struct URLSessionGitHubTransport: GitHubTransport {
    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.github.com/graphql")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func execute(body: Data, accessToken: GitHubAccessToken) async throws -> GitHubTransportResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitHubBar/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken.rawValue)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubTransportError.invalidResponse
        }

        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let retryAfter = headers["retry-after"].flatMap(TimeInterval.init)
            let rateLimitResetAt = headers["x-ratelimit-reset"]
                .flatMap(TimeInterval.init)
                .map(Date.init(timeIntervalSince1970:))
            throw GitHubTransportError.http(
                statusCode: httpResponse.statusCode,
                retryAfter: retryAfter,
                rateLimitResetAt: rateLimitResetAt
            )
        }

        return GitHubTransportResponse(statusCode: httpResponse.statusCode, headers: headers, data: data)
    }
}
