import Foundation

/// Everything the list can be narrowed by: free text in one place, plus quick toggles and a sidebar selection.
public struct FlowFilter: Equatable, Sendable {
    public enum Scope: String, CaseIterable, Sendable {
        case url = "URL", method = "Method", status = "Status", header = "Header", body = "Body"
        case host = "Host", all = "All"
    }

    /// One "<scope> contains <text>" condition, as a token in the search field.
    public struct Term: Hashable, Sendable {
        public var scope: Scope
        public var text: String

        public init(scope: Scope, text: String) {
            self.scope = scope; self.text = text
        }
    }

    public enum ContentKind: String, CaseIterable, Sendable { case json = "JSON", xml = "XML", html = "HTML", image = "Image", javascript = "JS", css = "CSS", form = "Form", other = "Other" }

    public var text = ""
    public var scope = Scope.url
    /// Scoped conditions that must all match, besides the free text.
    public var terms: [Term] = []
    public var methods: Set<String> = []
    /// Hundreds digit of the status code: 2 for 2xx. Errors without a response count as 0.
    public var statusClasses: Set<Int> = []
    public var contentKinds: Set<ContentKind> = []
    public var starredOnly = false
    public var webSocketOnly = false
    public var errorsOnly = false
    /// Sidebar selection: only this host / only this client app.
    public var host: String?
    public var app: String?
    /// Locale for the text search; not a filter, so `isActive` and `reset()` leave it alone.
    public var locale: Locale

    public init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    public var isActive: Bool {
        !text.isEmpty || !terms.isEmpty || !methods.isEmpty || !statusClasses.isEmpty || !contentKinds.isEmpty
            || starredOnly || webSocketOnly || errorsOnly || host != nil || app != nil
    }

    public mutating func reset() {
        self = FlowFilter(locale: locale)
    }

    public func matches(_ flow: Flow) -> Bool {
        if let host, !Self.host(flow, is: host) {
            return false
        }
        if let app, flow.request.clientApp != app {
            return false
        }
        if starredOnly, !flow.isStarred {
            return false
        }
        if webSocketOnly, flow.webSocketMessages.isEmpty, flow.response?.status != 101 {
            return false
        }
        if errorsOnly, !Self.isError(flow) {
            return false
        }
        if !methods.isEmpty, !methods.contains(flow.request.method.uppercased()) {
            return false
        }
        if !statusClasses.isEmpty, !statusClasses.contains(flow.response.map { $0.status / 100 } ?? 0) {
            return false
        }
        if !contentKinds.isEmpty, !contentKinds.contains(Self.kind(of: flow)) {
            return false
        }
        if !terms.allSatisfy({ $0.text.isEmpty || contains($0.text, in: $0.scope, of: flow) }) {
            return false
        }
        return text.isEmpty || contains(text, in: scope, of: flow)
    }

    public func apply(to flows: [Flow]) -> [Flow] {
        isActive ? flows.filter(matches) : flows
    }

    public static func isError(_ flow: Flow) -> Bool {
        flow.state == .failed || (flow.response?.status ?? 0) >= 400
    }

    /// `api.example.com` is shown under `example.com` in the sidebar, so choosing a domain includes its subdomains.
    static func host(_ flow: Flow, is host: String) -> Bool {
        flow.request.host == host || flow.request.host.hasSuffix("." + host)
    }

    public static func kind(of flow: Flow) -> ContentKind {
        let type = (flow.response?.headers.value(for: "Content-Type") ?? flow.request.headers.value(for: "Content-Type") ?? "").lowercased()
        if type.contains("json") {
            return .json
        }
        if type.contains("html") {
            return .html
        }
        if type.contains("xml") {
            return .xml
        }
        if type.contains("javascript") || type.contains("ecmascript") {
            return .javascript
        }
        if type.contains("css") {
            return .css
        }
        if type.hasPrefix("image/") {
            return .image
        }
        if type.contains("x-www-form-urlencoded") || type.contains("multipart/form-data") {
            return .form
        }
        return .other
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private func contains(_ text: String, in scope: Scope, of flow: Flow) -> Bool {
        func has(_ value: String) -> Bool {
            // POSIX catches ASCII that Turkish folds as I/ı; naming it keeps Foundation fast.
            value.range(of: text, options: .caseInsensitive, locale: Self.posix) != nil
                || value.range(of: text, options: .caseInsensitive, locale: locale) != nil
        }
        func has(_ data: Data) -> Bool {
            String(data: data, encoding: .utf8).map(has) ?? false
        }
        func matches(_ scope: Scope) -> Bool {
            switch scope {
            case .url: has(flow.request.url)
            case .method: has(flow.request.method)
            case .status: flow.response.map { has("\($0.status)") } ?? false
            case .header: (flow.request.headers + (flow.response?.headers ?? [])).contains { has($0.name) || has($0.value) }
            case .body: has(flow.request.body) || (flow.response.map { has($0.body) } ?? false)
            case .host: has(flow.request.host)
            case .all: false
            }
        }
        return scope == .all ? Scope.allCases.dropLast().contains(where: matches) || has(flow.comment ?? "") : matches(scope)
    }
}
