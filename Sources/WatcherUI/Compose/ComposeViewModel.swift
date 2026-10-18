import Foundation
import Observation
import WatcherCore

/// Everything the Compose window edits and how it turns into a request; the view only lays it out.
@MainActor @Observable
final class ComposeViewModel {
    enum Tab: String, CaseIterable {
        case params = "Params", headers = "Headers", auth = "Auth", body = "Body"
        var symbol: String {
            switch self { case .params: "slider.horizontal.3"; case .headers: "list.bullet.rectangle"; case .auth: "key"; case .body: "doc.plaintext" }
        }
    }

    enum Auth: String, CaseIterable { case none = "None", bearer = "Bearer Token", basic = "Basic" }

    /// Where the last send stands, so the window can say so.
    enum Phase: Equatable {
        case idle
        case sending
        case received(Flow)
        case failed(String)

        static func == (a: Phase, b: Phase) -> Bool {
            switch (a, b) {
            case (.idle, .idle), (.sending, .sending): true
            case let (.received(x), .received(y)): x.id == y.id
            case let (.failed(x), .failed(y)): x == y
            default: false
            }
        }
    }

    static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    var method = "GET"
    var address = "https://" {
        didSet {
            if address != oldValue {
                addressChanged()
            }
        }
    }

    var params: [KeyValue] = [] {
        didSet {
            if params != oldValue {
                syncURLFromParams()
            }
        }
    }

    var headers: [KeyValue] = [KeyValue("Accept", "*/*")]
    var auth = Auth.none
    var token = ""
    var username = ""
    var password = ""
    var bodyKind = RequestBodyBuilder.Kind.none
    var bodyText = ""
    var formRows: [KeyValue] = []
    var graphQLVariables = ""
    var file: KeyValue.FilePart?
    var followRedirects = false
    var tab = Tab.params
    private(set) var phase = Phase.idle
    /// A problem with the form itself (bad URL, unreadable cURL), shown next to the controls.
    var problem: String?

    /// The request this form was loaded from (Edit & Repeat), to show and reset what changed.
    private(set) var original: RequestRecord?

    /// Guards the URL ↔ params sync against bouncing between the two.
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    var isWebSocket: Bool {
        address.hasPrefix("ws://") || address.hasPrefix("wss://")
    }

    var isSending: Bool {
        phase == .sending
    }

    var result: Flow? {
        if case let .received(flow) = phase {
            flow
        } else {
            nil
        }
    }

    var isBodyInvalidJSON: Bool {
        bodyKind == .json && !bodyText.isEmpty && (try? JSONSerialization.jsonObject(with: Data(bodyText.utf8), options: .fragmentsAllowed)) == nil
    }

    func badge(_ tab: Tab) -> String? {
        switch tab {
        case .params: params.isEmpty ? nil : "\(params.filter(\.isEnabled).count)"
        case .headers: "\(headers.filter(\.isEnabled).count)"
        case .auth: auth == .none ? nil : "●"
        case .body: bodyKind == .none ? nil : bodyKind.rawValue
        }
    }

    // MARK: URL ↔ params

    private func addressChanged() {
        // A pasted `curl …` command fills the whole form instead of becoming a broken URL.
        if CurlImport.looksLikeCurl(address) {
            do { try load(CurlImport.parse(address)); problem = nil } catch { problem = "Cannot read the cURL command: \(error)" }
        } else {
            syncParamsFromURL()
        }
    }

    private func syncParamsFromURL() {
        guard !syncing, let components = URLComponents(string: address) else { return }
        let items = components.queryItems ?? []
        let current = params.filter(\.isEnabled)
        guard items.map(\.name) != current.map(\.name) || items.map({ $0.value ?? "" }) != current.map(\.value) else { return }
        syncing = true
        params = items.map { KeyValue($0.name, $0.value ?? "") } + params.filter { !$0.isEnabled }
        syncing = false
    }

    private func syncURLFromParams() {
        guard !syncing, var components = URLComponents(string: address) else { return }
        let enabled = params.filter { $0.isEnabled && !$0.name.isEmpty }
        components.queryItems = enabled.isEmpty ? nil : enabled.map { URLQueryItem(name: $0.name, value: $0.value) }
        guard let rebuilt = components.string, rebuilt != address else { return }
        syncing = true
        address = rebuilt
        syncing = false
    }

    // MARK: Loading a request

    func load(_ draft: RequestRecord, asOriginal: Bool = false) {
        if asOriginal {
            original = draft
        }
        method = draft.method
        syncing = true; address = draft.url; syncing = false
        syncParamsFromURL()
        let type = draft.headers.value(for: "content-type")
        let decoded = BodyDecoder.decode(draft.body, contentEncoding: draft.headers.value(for: "content-encoding")).data
        // Length, encoding and (for rebuilt bodies) the type are recomputed when sending.
        headers = draft.headers.filter { !["content-length", "content-encoding", "host"].contains($0.name.lowercased()) }.map { KeyValue($0.name, $0.value) }
        bodyKind = RequestBodyBuilder.kind(forContentType: type, body: decoded)
        switch bodyKind {
        case .form, .multipart:
            let fields = FormFields.parse(RequestRecord(method: draft.method, scheme: draft.scheme, host: draft.host, port: draft.port, path: "/", headers: draft.headers, body: decoded))
            formRows = fields.filter { $0.source != .query }.map { field in
                KeyValue(
                    field.name,
                    field.filename == nil ? field.value : "",
                    file: field.data.map { KeyValue.FilePart(filename: field.filename ?? "file", contentType: field.contentType ?? "application/octet-stream", data: $0) }
                )
            }
            headers.removeAll { $0.name.caseInsensitiveCompare("content-type") == .orderedSame }
        case .binary: file = KeyValue.FilePart(filename: "body", contentType: type ?? "application/octet-stream", data: decoded)
        default: bodyText = String(data: decoded, encoding: .utf8) ?? ""
        }
        tab = bodyKind == .none ? .params : .body
    }

    /// What the form changes compared with the original, in words: "method", "URL", "2 headers", "body".
    var changes: [String] {
        guard let original, let edited = try? build() else { return [] }
        var list: [String] = []
        if edited.method != original.method {
            list.append("method")
        }
        if edited.url != original.url {
            list.append("URL")
        }
        let dropped: Set = ["content-length", "content-encoding", "host", "content-type"]
        func normalized(_ headers: [Header]) -> Set<String> {
            Set(headers.filter { !dropped.contains($0.name.lowercased()) }.map { "\($0.name.lowercased()): \($0.value)" })
        }
        let headerChanges = normalized(edited.headers).symmetricDifference(normalized(original.headers)).count
        if headerChanges > 0 {
            list.append(headerChanges == 1 ? "1 header" : "\(headerChanges) headers")
        }
        let originalBody = BodyDecoder.decode(original.body, contentEncoding: original.headers.value(for: "content-encoding")).data
        if bodyKind != .multipart, edited.body != originalBody {
            list.append("body")
        }
        return list
    }

    func resetToOriginal() {
        guard let original else { return }
        params = []; formRows = []; file = nil; bodyText = ""; auth = .none
        load(original)
        problem = nil
        phase = .idle
    }

    // MARK: Building and sending

    func build() throws -> RequestRecord {
        guard let components = URLComponents(string: address.trimmingCharacters(in: .whitespaces)), let host = components.host, !host.isEmpty,
              let scheme = components.scheme, ["http", "https"].contains(scheme.lowercased())
        else {
            throw RequestBodyBuilder.BuildError(description: "Enter a full http:// or https:// URL.")
        }
        var list = headers.filter { $0.isEnabled && !$0.name.isEmpty }.map { Header($0.name, $0.value) }
        func setIfMissing(_ name: String, _ value: String) {
            if list.value(for: name) == nil {
                list.append(Header(name, value))
            }
        }
        switch auth {
        case .none: break
        case .bearer: if !token.isEmpty {
                setIfMissing("Authorization", "Bearer \(token)")
            }
        case .basic: setIfMissing("Authorization", "Basic " + Data("\(username):\(password)".utf8).base64EncodedString())
        }
        let boundary = RequestBodyBuilder.newBoundary()
        let body: Data
        switch bodyKind {
        case .none: body = Data()
        case .json, .text: body = Data(bodyText.utf8)
        case .form: body = RequestBodyBuilder.urlEncoded(formRows)
        case .multipart:
            body = RequestBodyBuilder.multipart(formRows, boundary: boundary)
            list.removeAll { $0.name.caseInsensitiveCompare("content-type") == .orderedSame } // the boundary must match this body
        case .graphQL: body = try RequestBodyBuilder.graphQL(query: bodyText, variables: graphQLVariables)
        case .binary:
            guard let file else { throw RequestBodyBuilder.BuildError(description: "Choose a file to send.") }
            body = file.data
            setIfMissing("Content-Type", file.contentType)
        }
        if let type = RequestBodyBuilder.contentType(for: bodyKind, boundary: boundary) {
            setIfMissing("Content-Type", type)
        }
        let lowered = scheme.lowercased()
        return RequestRecord(
            method: method,
            scheme: lowered,
            host: host,
            port: components.port ?? (lowered == "https" ? 443 : 80),
            path: (components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath) + (components.percentEncodedQuery.map { "?\($0)" } ?? ""),
            headers: list,
            body: body
        )
    }

    /// The messages a WebSocket compose sends after connecting, one per non-empty body line.
    var webSocketMessages: [String] {
        bodyText.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    struct WebSocketSession: Equatable {
        let url: URL
        let headers: [Header]
        let messages: [String]
    }

    /// What Connect opens for a ws:// or wss:// address: the enabled headers and one message per non-empty line.
    var webSocketSession: WebSocketSession? {
        guard isWebSocket, let url = URL(string: address) else { return nil }
        let enabled = headers.filter(\.isEnabled).map { Header($0.name, $0.value) }
        return WebSocketSession(url: url, headers: enabled, messages: webSocketMessages)
    }

    /// Sends through `perform` and records the outcome; a second send while one is running is ignored.
    func send(isProxyRunning: Bool, perform: (RequestRecord, Bool) async -> ResponseRecord) async {
        guard !isSending else { return }
        problem = nil
        guard isProxyRunning else { phase = .failed("Start the proxy to send requests."); return }
        let request: RequestRecord
        do { request = try build() } catch { phase = .failed("\(error)"); return }
        phase = .sending
        let started = now()
        let response = await perform(request, followRedirects)
        var flow = Flow(sequence: 0, request: request)
        flow.response = response; flow.state = .completed; flow.duration = now().timeIntervalSince(started)
        phase = .received(flow)
        // Watcher answers 502/504 itself when the server cannot be reached; the body says why, the note says where to look.
        if response.status >= 500 {
            problem = "The server answered \(response.status) \(HTTPStatus.reason(response.status)). See the response below."
        }
    }
}
