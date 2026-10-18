import Foundation
import WatcherCore

public extension RequestRecord {
    static func fixture(
        method: String = "GET",
        scheme: String = "https",
        host: String = "api.example.com",
        port: Int = 443,
        path: String = "/",
        headers: [Header] = [],
        body: Data = Data(),
        clientApp: String? = nil
    ) -> RequestRecord {
        RequestRecord(
            method: method,
            scheme: scheme,
            host: host,
            port: port,
            path: path,
            headers: headers,
            body: body,
            clientApp: clientApp
        )
    }

    /// Splits `url` the way a captured request stores it; the port defaults to the scheme's.
    static func fixture(
        method: String = "GET",
        url: String,
        headers: [Header] = [],
        body: Data = Data()
    ) -> RequestRecord {
        guard let components = URLComponents(string: url), let scheme = components.scheme, let host = components.host
        else {
            preconditionFailure("fixture URL must be absolute: \(url)")
        }
        return fixture(
            method: method,
            scheme: scheme,
            host: host,
            port: components.port ?? (scheme == "https" ? 443 : 80),
            path: components.percentEncodedPath + (components.percentEncodedQuery.map { "?\($0)" } ?? ""),
            headers: headers,
            body: body
        )
    }
}
