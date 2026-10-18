import Foundation

/// The request a browser would send after a redirect: the method, body and credentials follow the same rules.
enum RedirectHop {
    private static let statuses: Set<Int> = [301, 302, 303, 307, 308]
    private static let credentialHeaders: Set<String> = ["authorization", "cookie", "proxy-authorization"]

    static func next(after response: ResponseRecord, from current: RequestRecord) -> RequestRecord? {
        guard statuses.contains(response.status),
              let location = response.headers.value(for: "location"),
              let target = URL(string: location, relativeTo: URL(string: current.url)),
              let components = URLComponents(url: target.absoluteURL, resolvingAgainstBaseURL: true),
              let host = components.host, !host.isEmpty else { return nil }
        let scheme = components.scheme ?? current.scheme
        let port = components.port ?? RequestRecord.defaultPort(for: scheme)
        let crossOrigin = scheme != current.scheme || host.lowercased() != current.host.lowercased()
            || port != current.port
        let changesMethod = response.status == 303
            || ((response.status == 301 || response.status == 302) && current.method == "POST")
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return RequestRecord(
            method: changesMethod ? "GET" : current.method, scheme: scheme, host: host, port: port,
            path: (components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath) + query,
            headers: current.headers.filter {
                let name = $0.name.lowercased()
                return name != "host" && !(changesMethod && name.hasPrefix("content-"))
                    && !(crossOrigin && credentialHeaders.contains(name))
            },
            body: changesMethod ? Data() : current.body
        )
    }
}
