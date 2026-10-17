import Foundation
import SwiftTreeSitter
import TreeSitterCSS
import TreeSitterHTML
import TreeSitterJavaScript
import TreeSitterJSON

/// A parsed document that can answer "which tokens are in this range?" in milliseconds, however large the text is.
///
/// Parsing is the slow part (about 2.5 s for 30 MB of JSON) and must be done off the main thread; asking for the tokens of the
/// visible lines afterwards is cheap, so a viewer only ever colours what is on screen.
public final class SyntaxIndex: @unchecked Sendable {
    private let queries: [(query: Query, kind: SyntaxHighlighter.Kind)]
    private let language: Language
    private let lock = NSLock()
    private var tree: MutableTree?

    public static func supports(_ language: BodyLanguage) -> Bool {
        grammar(for: language) != nil
    }

    public init?(language bodyLanguage: BodyLanguage) {
        guard let (language, patterns, keywords) = Self.grammar(for: bodyLanguage) else { return nil }
        self.language = language
        func compile(_ pattern: String) -> Query? {
            try? Query(language: language, data: Data(pattern.utf8))
        }
        // Each pattern is compiled on its own so one that a grammar version does not know cannot disable the rest;
        // keywords are anonymous nodes, so those the grammar lacks are dropped one by one.
        var compiled = patterns.compactMap { pattern, kind in compile(pattern).map { ($0, kind) } }
        let known = keywords.filter { compile("\"\($0)\" @k") != nil }
        if !known.isEmpty, let query = compile("[\(known.map { "\"\($0)\"" }.joined(separator: " "))] @k") {
            compiled.insert((query, .keyword), at: 0)
        }
        queries = compiled
    }

    /// Blocks for as long as the document is large; call from a background task. Replaces any earlier parse.
    public func parse(_ text: String) {
        let parser = Parser()
        guard (try? parser.setLanguage(language)) != nil, let parsed = parser.parse(text) else { return }
        lock.withLock { tree = parsed }
    }

    /// Non-overlapping tokens that intersect `range` (UTF-16 offsets). Later patterns win where two capture the same text.
    public func tokens(in range: NSRange) -> [SyntaxHighlighter.Token] {
        lock.lock(); defer { lock.unlock() }
        guard let tree else { return [] }
        var byRange: [NSRange: (kind: SyntaxHighlighter.Kind, order: Int)] = [:]
        for (order, entry) in queries.enumerated() {
            let cursor = entry.query.execute(in: tree)
            cursor.setRange(range)
            for match in cursor {
                for capture in match.captures where capture.range.length > 0 {
                    byRange[capture.range] = (entry.kind, order)
                }
            }
        }
        var result: [SyntaxHighlighter.Token] = []
        var end = 0
        for (captured, value) in byRange.sorted(by: { ($0.key.location, -$0.key.length) < ($1.key.location, -$1.key.length) }) {
            guard captured.location >= end else { continue } // nested inside a token that is already coloured
            result.append(.init(range: captured, kind: value.kind))
            end = NSMaxRange(captured)
        }
        return result
    }

    // MARK: Grammars

    private static func grammar(for language: BodyLanguage) -> (Language, [(String, SyntaxHighlighter.Kind)], [String])? {
        switch language {
        case .json:
            return (Language(language: tree_sitter_json()), [
                ("(string) @s", .string), ("(pair key: (string) @k)", .key), ("(number) @n", .number),
                ("[(true) (false) (null)] @k", .keyword),
            ], [])
        case .html, .xml, .plist:
            return (Language(language: tree_sitter_html()), [
                ("(tag_name) @t", .tag), ("(erroneous_end_tag_name) @t", .tag), ("(attribute_name) @a", .attribute),
                ("(quoted_attribute_value) @s", .string), ("(attribute_value) @s", .string), ("(entity) @v", .variable),
                ("(doctype) @t", .type), ("(comment) @c", .comment),
            ], [])
        case .css:
            return (Language(language: tree_sitter_css()), [
                ("(tag_name) @t", .tag), ("(class_name) @t", .tag), ("(id_name) @t", .tag), ("(property_name) @a", .attribute),
                ("(integer_value) @n", .number), ("(float_value) @n", .number), ("(color_value) @n", .number),
                ("(string_value) @s", .string), ("(at_keyword) @k", .keyword), ("(comment) @c", .comment),
            ], [])
        case .javascript:
            let keywords = "function const let var return if else for while do switch case break continue new this class extends import export from default async await try catch finally throw typeof instanceof in of delete void yield static super"
            return (Language(language: tree_sitter_javascript()), [
                ("(property_identifier) @a", .attribute), ("(number) @n", .number),
                ("[(true) (false) (null) (undefined)] @k", .keyword),
                ("(regex) @s", .string), ("(string) @s", .string), ("(template_string) @s", .string), ("(comment) @c", .comment),
            ], keywords.split(separator: " ").map(String.init))
        default:
            return nil
        }
    }
}
