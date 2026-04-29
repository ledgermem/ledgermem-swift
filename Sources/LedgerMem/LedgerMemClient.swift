import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class MnemoClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.getmnemo.xyz")!
    private static let version = "0.1.0"
    public static let defaultMaxRetries = 3
    private static let retryBaseDelayNs: UInt64 = 200_000_000
    private static let retryMaxDelayNs: UInt64 = 5_000_000_000

    private let baseURL: URL
    private let apiKey: String
    private let workspaceId: String
    private let transport: HTTPTransport
    private let maxRetries: Int

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(
        apiKey: String,
        workspaceId: String,
        baseURL: URL? = nil,
        transport: HTTPTransport = URLSession.shared,
        maxRetries: Int = defaultMaxRetries
    ) {
        self.apiKey = apiKey
        self.workspaceId = workspaceId
        self.baseURL = baseURL
            ?? ProcessInfo.processInfo.environment["GETMNEMO_API_URL"].flatMap(URL.init(string:))
            ?? Self.defaultBaseURL
        self.transport = transport
        self.maxRetries = max(0, maxRetries)
    }

    // MARK: - Public API

    public func search(query: String, limit: Int? = nil, actorId: String? = nil) async throws -> SearchResponse {
        var body: [String: AnyCodable] = ["query": AnyCodable(query)]
        if let limit { body["limit"] = AnyCodable(limit) }
        if let actorId { body["actorId"] = AnyCodable(actorId) }
        return try await send("POST", path: "/v1/search", jsonBody: body)
    }

    public func create(content: String, metadata: [String: AnyCodable]? = nil, actorId: String? = nil) async throws -> Memory {
        var body: [String: AnyCodable] = ["content": AnyCodable(content)]
        if let metadata { body["metadata"] = AnyCodable(metadata) }
        if let actorId { body["actorId"] = AnyCodable(actorId) }
        return try await send("POST", path: "/v1/memories", jsonBody: body)
    }

    public func update(id: String, content: String? = nil, metadata: [String: AnyCodable]? = nil) async throws -> Memory {
        var body: [String: AnyCodable] = [:]
        if let content { body["content"] = AnyCodable(content) }
        if let metadata { body["metadata"] = AnyCodable(metadata) }
        return try await send("PATCH", path: "/v1/memories/\(escape(id))", jsonBody: body)
    }

    public func delete(id: String) async throws {
        let (data, response) = try await sendRaw("DELETE", path: "/v1/memories/\(escape(id))", body: nil, query: nil)
        try ensureSuccess(response, data: data)
    }

    public func list(limit: Int? = nil, cursor: String? = nil, actorId: String? = nil) async throws -> ListResponse {
        var query: [URLQueryItem] = []
        if let limit { query.append(.init(name: "limit", value: String(limit))) }
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        if let actorId { query.append(.init(name: "actorId", value: actorId)) }
        return try await send("GET", path: "/v1/memories", query: query.isEmpty ? nil : query)
    }

    // MARK: - Internals

    private func send<R: Decodable>(_ method: String, path: String, jsonBody: [String: AnyCodable]? = nil, query: [URLQueryItem]? = nil) async throws -> R {
        let bodyData = try jsonBody.map { try encoder.encode($0) }
        let (data, response) = try await sendRaw(method, path: path, body: bodyData, query: query)
        try ensureSuccess(response, data: data)
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw MnemoError.decoding(String(describing: error))
        }
    }

    private func sendRaw(_ method: String, path: String, body: Data?, query: [URLQueryItem]?) async throws -> (Data, HTTPURLResponse) {
        // Build the URL via URLComponents using `percentEncodedPath` so any
        // encoding we already applied to the id segment is preserved verbatim.
        // `appendingPathComponent` and `components.path =` both treat their
        // argument as raw and re-encode `%`, which double-encodes path ids.
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw MnemoError.invalidURL
        }
        let basePath = components.percentEncodedPath
        let trimmed = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let normalized = path.hasPrefix("/") ? path : "/\(path)"
        components.percentEncodedPath = trimmed + normalized
        if let query { components.queryItems = query }
        guard let url = components.url else { throw MnemoError.invalidURL }

        var attempt = 0
        while true {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue(workspaceId, forHTTPHeaderField: "x-workspace-id")
            req.setValue("getmnemo-swift/\(Self.version)", forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            do {
                let (data, response) = try await transport.send(req)
                if Self.isRetryable(status: response.statusCode), attempt < maxRetries {
                    let hint = Self.retryAfterNs(from: response)
                    let delay = hint ?? Self.retryDelayNs(attempt: attempt)
                    try await Task.sleep(nanoseconds: delay)
                    attempt += 1
                    continue
                }
                return (data, response)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .cancelled {
                // URLSession surfaces caller cancellation as URLError(.cancelled);
                // treat it like CancellationError rather than a retryable failure.
                throw urlError
            } catch {
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: Self.retryDelayNs(attempt: attempt))
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }

    private static func isRetryable(status: Int) -> Bool {
        // 501 Not Implemented is permanent — retrying wastes round-trips.
        if status == 501 { return false }
        return status == 429 || (500..<600).contains(status)
    }

    private static func retryDelayNs(attempt: Int) -> UInt64 {
        let shift = min(attempt, 20)
        let capped = min(retryBaseDelayNs &* (UInt64(1) << shift), retryMaxDelayNs)
        return UInt64.random(in: 0...capped)
    }

    /// Parse a Retry-After header (delta-seconds form), capped at
    /// `retryMaxDelayNs`. HTTP-date form is intentionally not supported
    /// here to avoid pulling in date-parsing surface; servers issuing it
    /// fall back to backoff.
    private static func retryAfterNs(from response: HTTPURLResponse) -> UInt64? {
        let raw = (response.value(forHTTPHeaderField: "Retry-After")
            ?? response.value(forHTTPHeaderField: "retry-after"))?
            .trimmingCharacters(in: .whitespaces)
        guard let raw, !raw.isEmpty, let secs = UInt64(raw) else { return nil }
        let ns = secs.multipliedReportingOverflow(by: 1_000_000_000)
        if ns.overflow { return retryMaxDelayNs }
        return min(ns.partialValue, retryMaxDelayNs)
    }

    private func ensureSuccess(_ response: HTTPURLResponse, data: Data) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        let body = String(data: data, encoding: .utf8) ?? ""
        throw MnemoError.http(status: response.statusCode, body: body)
    }

    /// Percent-encode an identifier so it is safe to inject as a single path
    /// segment. `.urlPathAllowed` keeps "/" intact, which would let an id
    /// like "..%2F..%2Fadmin" smuggle in extra segments — restrict the
    /// allowed set to RFC 3986 unreserved characters instead.
    private func escape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
