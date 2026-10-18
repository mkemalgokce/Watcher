import WatcherCore

extension ComposeViewModel {
    /// Takes up the request another window handed over (Edit & Repeat, a pasted cURL), once.
    func loadDraft(from router: WindowRouter) {
        guard let draft = router.composeDraft else { return }
        router.composeDraft = nil
        load(draft, asOriginal: router.composeSource != nil)
    }

    /// The banner's second line while editing.
    var changesSummary: String {
        let list = changes
        return list.isEmpty
            ? "No changes yet: sending repeats it as captured."
            : "Changed: \(list.joined(separator: ", "))"
    }

    var hasChanges: Bool {
        !changes.isEmpty
    }

    /// The request to compare with the original's answer: only for an edited capture that has been answered.
    var comparableRequest: RequestRecord? {
        guard original != nil, case .received = phase else { return nil }
        return try? build()
    }

    var waitingText: String {
        "Waiting for \((try? build().host) ?? "the server")…"
    }

    func beautifyBody() {
        bodyText = JSONFormatter.pretty(bodyText)
    }

    func minifyBody() {
        bodyText = JSONFormatter.minify(bodyText)
    }

    /// Keeps the current file when the panel is cancelled or the file cannot be read.
    func chooseFile(using picker: FilePicker) async {
        if let chosen = await picker.choosePart() {
            file = chosen
        }
    }

    /// Connect for a ws:// or wss:// address, Send otherwise. Connecting hands the session over and closes the window.
    func submit(using actions: RequestActions, isProxyRunning: Bool, dismiss: () -> Void) async {
        if isProxyRunning, let session = webSocketSession {
            actions.composeWebSocket(url: session.url, headers: session.headers, messages: session.messages)
            return dismiss()
        }
        await send(isProxyRunning: isProxyRunning) { await actions.perform($0, followRedirects: $1) }
    }

    func copyAsCURL(using actions: RequestActions) {
        do {
            try actions.copy(actions.code(for: build(), as: .curl), "cURL copied")
        } catch {
            problem = "\(error)"
        }
    }
}
