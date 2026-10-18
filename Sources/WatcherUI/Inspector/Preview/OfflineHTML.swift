import WebKit

/// Shows an HTML page only after every network load is blocked, so a failure to block never lets a page reach out.
enum OfflineHTML {
    static let unavailable = "<p style=\"font-family:-apple-system\">This page cannot be previewed offline.</p>"

    /// `blockNetwork` reports whether blocking is in place; `show` gets the page, or `unavailable` when it is not.
    @MainActor
    static func load(
        _ html: String,
        blockNetwork: (@escaping @MainActor (Bool) -> Void) -> Void,
        show: @escaping @MainActor (String) -> Void
    ) {
        blockNetwork { isBlocked in show(isBlocked ? html : unavailable) }
    }

    /// Compiles the block-everything rule list and hands it to `completion`; nil when WebKit refuses.
    typealias RuleCompiler = (@escaping @MainActor (WKContentRuleList?) -> Void) -> Void

    static let liveCompiler: RuleCompiler = { completion in
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "watcher.block-all",
            encodedContentRuleList: #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
        ) { list, _ in
            MainActor.assumeIsolated { completion(list) }
        }
    }

    /// Adds the compiled rule list to `controller` and reports whether it is in place.
    @MainActor
    static func blockNetwork(
        in controller: WKUserContentController,
        compile: RuleCompiler,
        done: @escaping @MainActor (Bool) -> Void
    ) {
        compile { list in
            if let list {
                controller.add(list)
            }
            done(list != nil)
        }
    }
}
