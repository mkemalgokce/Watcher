import Foundation
import NIOSSL
@testable import WatcherCore

/// Engine + echo origin, with requests sent through the proxy. `host` (`upstream.test` unless told otherwise)
/// resolves to the echo origin.
public final class Harness {
    public let upstream: TestUpstream
    public let engine: WatcherEngine
    public var proxyPort = 0
    public var originURL: String {
        "http://\(authorityHost):\(upstream.port)"
    }

    private let host: String
    private let loopbackAddress: String
    /// `host` as it is written in a URL, an IPv6 literal in brackets.
    private var authorityHost: String {
        host.contains(":") ? "[\(host)]" : host
    }

    /// The engine's data folder when it is on disk, removed when the harness goes away.
    private let directory: TemporaryDirectory?

    /// `clientApp` identifies the program behind a client port; by default none, so no test runs `lsof` per connection.
    /// With `origin`, the echo origin speaks HTTPS and the proxy trusts `origin.trust` upstream; with `files`, the
    /// engine's data lives in that fake file system instead of a folder on disk.
    public init(
        host: String = "upstream.test",
        origin: OriginAuthority? = nil,
        files: FileAccessFake? = nil,
        loopbackAddress: String? = nil,
        clientApp: @escaping @Sendable (Int) -> ClientIdentity? = { _ in nil }
    ) throws {
        let loopbackAddress = loopbackAddress ?? (host.contains(":") ? host : "127.0.0.1")
        self.host = host
        self.loopbackAddress = loopbackAddress
        upstream = try TestUpstream(tls: origin?.serverContext(for: host), bindHost: loopbackAddress)
        let trust = try origin?.trust ?? .makeClientConfiguration()
        let access = files?.access ?? .live
        directory = files == nil ? try TemporaryDirectory() : nil
        let location = directory?.url ?? URL(fileURLWithPath: "/fake-home/.watcher")
        engine = try WatcherEngine(directory: location, files: access) { store, authority in
            ProxyServer(
                store: store, authority: authority, upstreamTLS: trust, clientApp: clientApp, files: access
            )
        }
    }

    public func start(configure: (inout WatcherSettings) -> Void = { _ in }) async throws {
        try await upstream.start()
        try engine.settings.update {
            let spoof = DNSSpoofRule(host: host, address: loopbackAddress)
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
        try? await engine.stop(); await upstream.stop()
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
