import SwiftUI
import WatcherCore

/// Context menu of the request list; the same actions are in the Request menu of the menu bar.
struct FlowActions: View {
    @Environment(AppModel.self) private var model
    @Environment(FlowListViewModel.self) private var list
    @Environment(RequestActions.self) private var actions
    let ids: Set<Flow.ID>
    var onComment: (Flow) -> Void = { _ in }

    var body: some View {
        if let flow = list.flows.first(where: { ids.contains($0.id) }) {
            let request = flow.request
            let commands = model.requestCommands(for: flow, ids: ids)
            item("Repeat", "arrow.clockwise", .repeatRequest, in: commands)
            item("Edit & Repeat…", "square.and.pencil", .editAndRepeat, in: commands)
            Divider()
            item(commands.starTitle, flow.isStarred ? "star.slash" : "star", .toggleStar, in: commands)
            Button("Add Comment…", systemImage: "text.bubble") { onComment(flow) }
            Menu("Copy as", systemImage: "doc.on.doc") {
                item("URL", nil, .copyURL, in: commands)
                ForEach(CodeGenerator.Language.allCases, id: \.self) { language in
                    Button(language.rawValue) { actions.copy(actions.code(for: request, as: language)) }
                }
            }
            Menu("Response Body", systemImage: "doc") {
                let body = ExchangeText.body(of: flow, side: .response)
                let name = ExchangeText.suggestedFileName(for: flow, side: .response)
                item("Save…", "square.and.arrow.down", .saveResponseBody, in: commands)
                OpenWithMenu(data: body, name: name, contentType: flow.response?.headers.value(for: "content-type"))
                Button("Copy as Text", systemImage: "doc.on.doc") {
                    actions.copy(String(decoding: body, as: UTF8.self), "Response body copied")
                }
                Button("Copy as Base64") { actions.copy(body.base64EncodedString(), "Response body copied as Base64") }
            }
            .disabled(flow.response?.body.isEmpty ?? true)
            Menu("Copy Headers", systemImage: "list.bullet.rectangle") {
                item("Request Headers", nil, .copyRequestHeaders, in: commands)
                item("Response Headers", nil, .copyResponseHeaders, in: commands)
            }
            if commands.isEnabled(.saveRequestBody) {
                item("Save Request Body…", "square.and.arrow.up", .saveRequestBody, in: commands)
            }
            item("Set as Compare Base", "arrow.left.arrow.right", .setCompareBase, in: commands)
            item("Mock This Response", "theatermasks", .mockResponse, in: commands)
            Divider()
            Button("Add Breakpoint for this URL", systemImage: "pause.circle") { actions.addBreakpoint(for: request) }
            Button("Block this Host", systemImage: "nosign") { actions.blockHost(request.host) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { commands.perform(.delete) }
        }
    }

    private func item(
        _ title: String, _ symbol: String?, _ command: RequestCommands.Command, in commands: RequestCommands
    ) -> some View {
        Button {
            commands.perform(command)
        } label: {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .disabled(!commands.isEnabled(command))
    }
}
