import AsyncHTTPClient
import Foundation
@testable import WatcherCore

/// Engine + echo origin + a client that talks through the proxy. `upstream.test` resolves to the echo origin.
public final class Harness {
    public let upstream = TestUpstream()
    public let engine: WatcherEngine
    public let client: HTTPClient
    public var proxyPort = 0
    public var originURL: String {
        "http://upstream.test:\(upstream.port)"
    }

    public init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watcher-test-\(UUID().uuidString)")
        engine = try WatcherEngine(directory: directory)
        client = HTTPClient(eventLoopGroupProvider: .singleton)
    }

    public func start(configure: (inout WatcherSettings) -> Void = { _ in }) async throws {
        try await upstream.start()
        try engine.settings.update {
            let spoof = DNSSpoofRule(host: "upstream.test", address: "127.0.0.1")
            $0.dnsSpoofing = RuleSet(isEnabled: true, rules: [spoof])
            configure(&$0)
        }
        proxyPort = try await engine.start(port: 0)
    }

    public func reconfigure(_ change: (inout WatcherSettings) -> Void) async throws {
        try engine.settings.update(change)
        await engine.apply(engine.settings.value)
    }

    /// Plain-HTTP request through the proxy (absolute-form URI, like a browser would send).
    public func get(
        _ path: String,
        method: String = "GET",
        headers: [(String, String)] = []
    ) async throws -> (status: Int, body: String) {
        let session = proxiedSession(timeout: 10)
        defer { session.invalidateAndCancel() }
        var request = try URLRequest(url: originURL(path))
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: request)
        // swiftlint:disable:next optional_data_string_conversion
        return try (http(response).statusCode, String(decoding: data, as: UTF8.self))
    }

    public func post(_ path: String, body: Data) async throws -> String {
        let session = proxiedSession(timeout: 30)
        defer { session.invalidateAndCancel() }
        var request = try URLRequest(url: originURL(path))
        request.httpMethod = "POST"
        let (data, _) = try await session.upload(for: request, from: body)
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }

    /// GET through the proxy that also returns the response headers.
    public func getWithHeaders(_ path: String) async throws -> (status: Int, headers: [String: String]) {
        let session = proxiedSession(timeout: nil)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(from: originURL(path))
        let http = try http(response)
        let headers = http.allHeaderFields.compactMap { key, value in
            (key as? String).map { ($0.lowercased(), "\(value)") }
        }
        return (http.statusCode, Dictionary(uniqueKeysWithValues: headers))
    }

    public func stop() async {
        try? await engine.stop(); await upstream.stop(); try? await client.shutdown()
    }

    private func proxiedSession(timeout: TimeInterval?) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": proxyPort]
        if let timeout {
            configuration.timeoutIntervalForRequest = timeout
        }
        return URLSession(configuration: configuration)
    }

    private func originURL(_ path: String) throws -> URL {
        guard let url = URL(string: originURL + path) else { throw TestSupportError("not a URL: \(originURL + path)") }
        return url
    }

    private func http(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw TestSupportError("not an HTTP response: \(response)")
        }
        return http
    }
}
