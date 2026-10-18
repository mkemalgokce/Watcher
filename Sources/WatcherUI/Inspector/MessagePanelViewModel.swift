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
            default: true
            }
        }
    }

    /// The chosen section, except that a request without a body shows its parameters (or headers) instead of an empty
    /// Body, and a section this exchange does not have (Messages on plain HTTP) falls back to Body.
    func section(chosen raw: String) -> Section {
        var chosen = Section(rawValue: raw) ?? .body
        if !available.contains(chosen) {
            chosen = .body
        }
        guard side == .request, chosen == .body, flow.request.body.isEmpty else { return chosen }
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
