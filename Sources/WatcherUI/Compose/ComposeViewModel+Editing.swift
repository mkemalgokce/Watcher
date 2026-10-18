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

    func copyAsCURL(using actions: RequestActions) {
        do {
            try actions.copy(actions.code(for: build(), as: .curl), "cURL copied")
        } catch {
            problem = "\(error)"
        }
    }
}
