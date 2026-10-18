import Foundation
import WatcherCore

/// File names and text that save, copy and Open With offer for one half of an exchange.
enum ExchangeText {
    /// "users.json" for GET /v1/users answered with JSON: the last path component, with the content type's extension.
    static func suggestedFileName(for flow: Flow, side: MessageSide) -> String {
        let last = URL(string: flow.request.url)?.lastPathComponent ?? ""
        let base = last.isEmpty || last == "/" ? side.rawValue : last
        guard (base as NSString).pathExtension.isEmpty,
              let ext = FileExtension.preferred(forContentType: flow.headers(side).value(for: "content-type"))
        else { return base }
        return "\(base).\(ext)"
    }

    /// Headers as they appear on the wire, one per line.
    static func headerText(of flow: Flow, side: MessageSide) -> String {
        flow.headers(side).map { "\($0.name): \($0.value)" }.joined(separator: "\n")
    }

    /// The decoded (Content-Encoding undone) body of one side.
    static func body(of flow: Flow, side: MessageSide) -> Data {
        BodyDecoder.decode(flow.body(side), contentEncoding: flow.headers(side).value(for: "content-encoding")).data
    }

    static let bodyLimit = 1_000_000

    static func rawMessage(of flow: Flow, side: MessageSide) -> String {
        let headers: [Header], body: Data, first: String
        let version = flow.upstreamHTTPVersion ?? "HTTP/1.1"
        if side == .request {
            first = "\(flow.request.method) \(flow.request.path) \(version)"
            let host = flow.request.headers.value(for: "host") == nil ? [Header("Host", flow.request.host)] : []
            headers = host + flow.request.headers
            body = flow.request.body
        } else {
            let status = flow.response?.status ?? 0
            first = "\(version) \(status) \(HTTPStatus.reason(status))"
            headers = flow.response?.headers ?? []
            body = flow.response?.body ?? Data()
        }
        return ([first] + headers.map { "\($0.name): \($0.value)" }).joined(separator: "\n") + "\n\n" + bodyText(body)
    }

    /// UTF-8 text, cut at the limit without splitting a character; anything else is described, not shown.
    static func bodyText(_ body: Data) -> String {
        guard !body.isEmpty else { return "" }
        var end = min(body.count, bodyLimit)
        // A cut can fall inside a multi-byte character; back off to the character's first byte.
        while end < body.count, end > 0, body[body.startIndex + end] & 0b1100_0000 == 0b1000_0000 {
            end -= 1
        }
        guard let text = String(data: body.prefix(end), encoding: .utf8) else {
            return "<\(body.count) bytes of binary data>"
        }
        return end < body.count ? text + "\n… \(body.count - end) more bytes not shown" : text
    }
}
