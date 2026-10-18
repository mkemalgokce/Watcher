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
}
