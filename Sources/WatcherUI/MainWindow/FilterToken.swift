import WatcherCore

/// One condition in the search field, shown as a token: a method, a status class, a content type, or "<where> contains <text>".
/// Typing offers them as suggestions, so where the text is looked for is chosen right in the field.
enum FilterToken: Hashable, Identifiable {
    case method(String)
    /// Hundreds digit of the status; 0 is a request that got no response.
    case status(Int)
    case kind(FlowFilter.ContentKind)
    case term(FlowFilter.Term)

    var id: Self {
        self
    }

    private static let statuses = [2, 3, 4, 5, 0]
    private static let textScopes: [FlowFilter.Scope] = [.url, .header, .body, .all]
    private static let maxHosts = 5

    var title: String {
        switch self {
        case let .method(method): method
        case let .status(code): code == 0 ? "Failed" : "\(code)xx"
        case let .kind(kind): kind.rawValue
        case let .term(term) where term.scope == .host: "Host: \(term.text)"
        case let .term(term): "\(term.scope == .all ? "Anywhere" : term.scope.rawValue) contains “\(term.text)”"
        }
    }

    var symbol: String {
        switch self {
        case .method: "arrow.left.arrow.right"
        case .status: "number"
        case .kind: "doc"
        case let .term(term) where term.scope == .host: "globe"
        case .term: "text.magnifyingglass"
        }
    }

    /// The tokens a filter holds, grouped by kind so they keep a stable order.
    static func tokens(in filter: FlowFilter) -> [FilterToken] {
        RequestMethod.common.filter(filter.methods.contains).map(FilterToken.method)
            + statuses.filter(filter.statusClasses.contains).map(FilterToken.status)
            + FlowFilter.ContentKind.allCases.filter(filter.contentKinds.contains).map(FilterToken.kind)
            + filter.terms.map(FilterToken.term)
    }

    /// Sets what tokens control; the free text and the sidebar selection are left alone.
    static func apply(_ tokens: [FilterToken], to filter: inout FlowFilter) {
        filter.methods = []; filter.statusClasses = []; filter.contentKinds = []; filter.terms = []
        for token in tokens {
            switch token {
            case let .method(method): filter.methods.insert(method)
            case let .status(code): filter.statusClasses.insert(code)
            case let .kind(kind): filter.contentKinds.insert(kind)
            case let .term(term): filter.terms.append(term)
            }
        }
    }

    /// What to offer under the field: quick filters when it is empty; otherwise the quick filters the text names, matching
    /// hosts, then where to look for the text.
    static func suggestions(for typed: String, hosts: [String], excluding present: [FilterToken]) -> [FilterToken] {
        let text = typed.trimmingCharacters(in: .whitespaces)
        let offered: [FilterToken]
        if text.isEmpty {
            offered = statuses.map(FilterToken.status) + RequestMethod.common.map(FilterToken.method)
                + FlowFilter.ContentKind.allCases.map(FilterToken.kind)
        } else {
            let lower = text.lowercased()
            let named = statuses.map(FilterToken.status).filter { $0.title.lowercased().hasPrefix(lower) }
                + RequestMethod.common.filter { $0.lowercased().hasPrefix(lower) }.map(FilterToken.method)
                + FlowFilter.ContentKind.allCases.filter { $0.rawValue.lowercased().hasPrefix(lower) }
                .map(FilterToken.kind)
            let matchingHosts = hosts.filter { $0.lowercased().contains(lower) }.prefix(maxHosts)
                .map { FilterToken.term(.init(scope: .host, text: $0)) }
            offered = named + matchingHosts + textScopes.map { FilterToken.term(.init(scope: $0, text: text)) }
        }
        return offered.filter { !present.contains($0) }
    }
}
