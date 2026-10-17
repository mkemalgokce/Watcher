import Foundation
import Observation
import WatcherCore

/// The editable copy of one paused message and the rules for sending it on; the editor view only lays it out.
@MainActor @Observable
final class HitEditorViewModel {
    let hit: BreakpointCenter.Hit
    var urlText = ""
    var method = "GET"
    var status = ""
    var headers: [KeyValue] = []
    var bodyText = ""

    var isResponse: Bool {
        hit.phase == .response
    }

    var statusCode: Int? {
        Int(status.trimmingCharacters(in: .whitespaces)).flatMap { (100 ... 599).contains($0) ? $0 : nil }
    }

    var isURLValid: Bool {
        guard let components = URLComponents(string: urlText), let scheme = components.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && components.host?.isEmpty == false
    }

    var canExecute: Bool {
        isResponse ? statusCode != nil : isURLValid
    }

    var bodyLanguage: BodyLanguage {
        BodyLanguage.detect(
            contentType: headers.first { $0.isEnabled && $0.name.caseInsensitiveCompare("content-type") == .orderedSame }?.value,
            data: Data(bodyText.utf8)
        )
    }

    init(hit: BreakpointCenter.Hit) {
        self.hit = hit
        if let response = hit.response {
            status = "\(response.status)"
            headers = response.headers.map { KeyValue($0.name, $0.value) }
            bodyText = BodyFormatter.format(
                response.body,
                contentType: response.headers.value(for: "content-type"),
                contentEncoding: response.headers.value(for: "content-encoding")
            ).text
        } else {
            method = hit.request.method
            urlText = hit.request.url
            headers = hit.request.headers.map { KeyValue($0.name, $0.value) }
            bodyText = String(data: BodyDecoder.decode(hit.request.body, contentEncoding: hit.request.headers.value(for: "content-encoding")).data, encoding: .utf8) ?? ""
        }
    }

    func apply(_ template: BreakpointTemplate) {
        status = "\(template.status)"
        headers = template.headers.map { KeyValue($0.name, $0.value) }
        bodyText = template.body
    }

    /// What to send on, or nil while the form is invalid. The edited text is sent as it is, so stale
    /// Content-Length / Content-Encoding headers are dropped: they would describe the old bytes.
    func resolution() -> BreakpointCenter.Resolution? {
        guard canExecute else { return nil }
        let edited = headers.filter { $0.isEnabled && !$0.name.isEmpty && !["content-length", "content-encoding"].contains($0.name.lowercased()) }
            .map { Header($0.name, $0.value) }
        if var response = hit.response {
            response.status = statusCode ?? response.status
            response.headers = edited
            response.body = Data(bodyText.utf8)
            return .proceed(request: hit.request, response: response)
        }
        var request = hit.request
        request.method = method
        if let url = URLComponents(string: urlText), let host = url.host {
            request.scheme = url.scheme?.lowercased() ?? request.scheme
            request.host = host
            request.port = url.port ?? (request.scheme == "https" ? 443 : 80)
            request.path = (url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath) + (url.percentEncodedQuery.map { "?\($0)" } ?? "")
        }
        request.headers = edited
        request.body = Data(bodyText.utf8)
        return .proceed(request: request, response: nil)
    }
}
