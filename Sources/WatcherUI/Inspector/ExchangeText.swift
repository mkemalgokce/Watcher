import Foundation
import UniformTypeIdentifiers
import WatcherCore

/// File names and text that save, copy and Open With offer for one half of an exchange.
enum ExchangeText {
    /// "users.json" for GET /v1/users answered with JSON: the last path component, with the content type's extension.
    static func suggestedFileName(for flow: Flow, side: MessageSide) -> String {
        let last = URL(string: flow.request.url)?.lastPathComponent ?? ""
        let base = last.isEmpty || last == "/" ? side.rawValue : last
        let mimeType = flow.headers(side).value(for: "content-type")?.split(separator: ";").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard (base as NSString).pathExtension.isEmpty,
              let mimeType, let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension else { return base }
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
}
