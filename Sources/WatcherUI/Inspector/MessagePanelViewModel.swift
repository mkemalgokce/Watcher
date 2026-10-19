import Foundation
import WatcherCore

/// What one side of an exchange offers: its sections, which one to show, the badge counts and the size summary.
struct MessagePanelViewModel {
    typealias Section = MessagePanel.Section

    let flow: Flow
    let side: MessageSide
    let previewersActive: Bool
    let embedded: [Base64Segment]

    var headers: [Header] {
        flow.headers(side)
    }

    var fields: [FormField] {
        side == .request ? FormFields.parse(flow.request) : []
    }

    var cookies: [CookieEntry] {
        Cookies.entries(for: flow).filter { $0.source == (side == .request ? .request : .response) }
    }

    var available: [Section] {
        Section.allCases.filter { section in
            switch section {
            case .params: side == .request
            case .messages: side == .response && flow.isWebSocket
            case .previewers: side == .response && previewersActive
            case .decoded: !embedded.isEmpty
            // A request without a body (a GET) has no Body tab; a response keeps it to show it came back empty.
            case .body: side == .response || !flow.request.body.isEmpty
            default: true
            }
        }
    }

    /// The chosen section; one this exchange does not have (Messages on plain HTTP, Body on a GET) falls back to Body,
    /// or, without a Body, to the parameters or else the headers.
    func section(chosen raw: String) -> Section {
        let chosen = Section(rawValue: raw) ?? .body
        if available.contains(chosen) {
            return chosen
        }
        if available.contains(.body) {
            return .body
        }
        return fields.isEmpty ? .headers : .params
    }

    func count(_ section: Section) -> Int? {
        switch section {
        case .headers: headers.count
        case .params: fields.count
        case .cookies: cookies.count
        case .messages: flow.webSocketMessages.count
        case .decoded: embedded.count
        case .body, .raw, .previewers: nil
        }
    }

    /// "application/json · 1.2 KB"; a response always states its size, so an empty one reads "0 B" instead of looking
    /// unloaded.
    var detail: String {
        let body = flow.body(side)
        let type = headers.value(for: "content-type")?.split(separator: ";").first.map(String.init)
        let size = side == .response || !body.isEmpty ? Format.bytes(body.count) : nil
        return [type, size].compactMap(\.self).joined(separator: " · ")
    }
}
