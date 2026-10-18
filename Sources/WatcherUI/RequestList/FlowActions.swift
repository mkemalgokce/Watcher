import SwiftUI
import WatcherCore

/// Context menu of the request list; the same actions are in the Request menu of the menu bar.
struct FlowActions: View {
    @Environment(AppModel.self) private var model
    let ids: Set<Flow.ID>
    var onComment: (Flow) -> Void = { _ in }

    var body: some View {
        if let flow = model.flows.first(where: { ids.contains($0.id) }) {
            let request = flow.request
            Button("Repeat", systemImage: "arrow.clockwise") { model.repeatRequest(request) }
            Button("Edit & Repeat…", systemImage: "square.and.pencil") { model.editAndRepeat(flow) }
            Divider()
            Button(flow.isStarred ? "Remove Star" : "Star", systemImage: flow.isStarred ? "star.slash" : "star") { model.toggleStar(ids) }
            Button("Add Comment…", systemImage: "text.bubble") { onComment(flow) }
            Menu("Copy as", systemImage: "doc.on.doc") {
                Button("URL") { model.copy(request.url) }
                ForEach(CodeGenerator.Language.allCases, id: \.self) { language in
                    Button(language.rawValue) { model.copy(model.code(for: request, as: language)) }
                }
            }
            Menu("Response Body", systemImage: "doc") {
                let body = ExchangeText.body(of: flow, side: .response)
                let name = ExchangeText.suggestedFileName(for: flow, side: .response)
                Button("Save…", systemImage: "square.and.arrow.down") {
                    model.sessionFiles.saveBody(of: flow, side: .response)
                }
                OpenWithMenu(data: body, name: name, contentType: flow.response?.headers.value(for: "content-type"))
                Button("Copy as Text", systemImage: "doc.on.doc") { model.copy(String(decoding: body, as: UTF8.self), "Response body copied") }
                Button("Copy as Base64") { model.copy(body.base64EncodedString(), "Response body copied as Base64") }
            }
            .disabled(flow.response?.body.isEmpty ?? true)
            Menu("Copy Headers", systemImage: "list.bullet.rectangle") {
                Button("Request Headers") {
                    model.copy(ExchangeText.headerText(of: flow, side: .request), "Request headers copied")
                }
                Button("Response Headers") {
                    model.copy(ExchangeText.headerText(of: flow, side: .response), "Response headers copied")
                }
                .disabled(flow.response == nil)
            }
            if !flow.request.body.isEmpty {
                Button("Save Request Body…", systemImage: "square.and.arrow.up") {
                    model.sessionFiles.saveBody(of: flow, side: .request)
                }
            }
            Button("Set as Compare Base", systemImage: "arrow.left.arrow.right") { model.compare(withBase: flow) }
            Button("Mock This Response", systemImage: "theatermasks") { model.mockResponse(flow) }.disabled(flow.response == nil)
            Divider()
            Button("Add Breakpoint for this URL", systemImage: "pause.circle") {
                model.settings.breakpoints.isEnabled = true
                model.settings.breakpoints.rules.append(BreakpointRule(name: request.host, matching: MatchingRule(pattern: "\(request.host)\(request.path.split(separator: "?").first.map(String.init) ?? "/")")))
            }
            Button("Block this Host", systemImage: "nosign") {
                model.settings.blockList.isEnabled = true
                model.settings.blockList.rules.append(BlockRule(name: request.host, matching: MatchingRule(pattern: "\(request.host)/*")))
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(ids) }
        }
    }
}
