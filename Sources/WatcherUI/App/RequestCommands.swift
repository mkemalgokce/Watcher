import WatcherCore

/// What each request action does to one request and whether it is available, so the Request menu, the list's context
/// menu and the inspector's buttons offer the same actions with the same rules and the same feedback.
@MainActor
struct RequestCommands {
    enum Command: CaseIterable {
        case repeatRequest, editAndRepeat, toggleStar, copyCURL, copyURL, copyRequestHeaders, copyResponseHeaders
        case mockResponse, setCompareBase, saveResponseBody, saveRequestBody, delete
    }

    let flow: Flow?
    /// The requests Star and Delete apply to: the list's whole selection, or just `flow`.
    let ids: Set<Flow.ID>
    let actions: RequestActions
    let router: WindowRouter
    let sessionFiles: SessionFilesViewModel

    init(
        flow: Flow?, ids: Set<Flow.ID>? = nil, actions: RequestActions, router: WindowRouter,
        sessionFiles: SessionFilesViewModel
    ) {
        self.flow = flow; self.actions = actions; self.router = router; self.sessionFiles = sessionFiles
        self.ids = ids ?? flow.map { [$0.id] } ?? []
    }

    var starTitle: String {
        flow?.isStarred == true ? "Remove Star" : "Star"
    }

    func isEnabled(_ command: Command) -> Bool {
        guard let flow else { return false }
        switch command {
        case .mockResponse, .copyResponseHeaders: return flow.response != nil
        case .saveResponseBody: return !(flow.response?.body.isEmpty ?? true)
        case .saveRequestBody: return !flow.request.body.isEmpty
        case .delete: return !ids.isEmpty
        default: return true
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func perform(_ command: Command) { // one case per command
        guard let flow, isEnabled(command) else { return }
        switch command {
        case .repeatRequest: actions.repeatRequest(flow.request)
        case .editAndRepeat: actions.editAndRepeat(flow)
        case .toggleStar: actions.toggleStar(ids)
        case .copyCURL: actions.copy(actions.code(for: flow.request, as: .curl), "cURL copied")
        case .copyURL: actions.copy(flow.request.url, "URL copied")
        case .copyRequestHeaders:
            actions.copy(ExchangeText.headerText(of: flow, side: .request), "Request headers copied")
        case .copyResponseHeaders:
            actions.copy(ExchangeText.headerText(of: flow, side: .response), "Response headers copied")
        case .mockResponse: actions.mockResponse(flow)
        case .setCompareBase: router.compare(withBase: flow)
        case .saveResponseBody: sessionFiles.saveBody(of: flow, side: .response)
        case .saveRequestBody: sessionFiles.saveBody(of: flow, side: .request)
        case .delete: actions.delete(ids)
        }
    }
}
