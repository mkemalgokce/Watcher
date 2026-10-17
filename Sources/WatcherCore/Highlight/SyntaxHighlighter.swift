import Foundation

/// Splits text into coloured runs. Regular-expression based: good enough to make a body readable, not a full parser.
public enum SyntaxHighlighter {
    public enum Kind: String, Sendable, CaseIterable {
        case keyword, string, number, key, tag, attribute, comment, type, variable
    }

    public struct Token: Equatable, Sendable {
        /// UTF-16 range, directly usable with `NSAttributedString`.
        public let range: NSRange
        public let kind: Kind
        public init(range: NSRange, kind: Kind) {
            self.range = range; self.kind = kind
        }
    }

    private struct Rule { let pattern: String; let kind: Kind; var options: NSRegularExpression.Options = [] }

    /// Tokens in text order, never overlapping. Rules earlier in a language's list win over later ones.
    public static func tokens(in text: String, language: BodyLanguage) -> [Token] {
        let rules = rules(for: language)
        guard !rules.isEmpty, !text.isEmpty else { return [] }
        let ns = text as NSString
        var claimed = [Bool](repeating: false, count: ns.length)
        var found: [Token] = []
        for rule in rules {
            guard let regex = compiled(rule) else { continue }
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, match.range.length > 0 else { return }
                let range = match.range
                guard !claimed[range.location ..< range.location + range.length].contains(true) else { return }
                for i in range.location ..< range.location + range.length {
                    claimed[i] = true
                }
                found.append(Token(range: range, kind: rule.kind))
            }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    // MARK: Rules

    private static let string = #""(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'"#
    private static let number = #"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#

    private static func words(_ list: String) -> String {
        #"\b(?:"# + list.split(separator: " ").joined(separator: "|") + #")\b"#
    }

    private static func cLike(_ keywords: String, comment: String = #"//[^\n]*|/\*[\s\S]*?\*/"#, extra: [Rule] = []) -> [Rule] {
        [Rule(pattern: comment, kind: .comment), Rule(pattern: string, kind: .string)] + extra +
            [Rule(pattern: words(keywords), kind: .keyword), Rule(pattern: #"\b[A-Z][A-Za-z0-9_]*\b"#, kind: .type), Rule(pattern: number, kind: .number)]
    }

    private static func rules(for language: BodyLanguage) -> [Rule] {
        switch language {
        case .json:
            [
                Rule(pattern: #""(?:[^"\\\n]|\\.)*"(?=\s*:)"#, kind: .key),
                Rule(pattern: #""(?:[^"\\\n]|\\.)*""#, kind: .string),
                Rule(pattern: number, kind: .number),
                Rule(pattern: words("true false null"), kind: .keyword),
            ]
        case .xml, .html, .plist:
            [
                Rule(pattern: #"<!--[\s\S]*?-->"#, kind: .comment),
                Rule(pattern: #"<!\[CDATA\[[\s\S]*?\]\]>|<![A-Za-z][^>]*>|<\?[\s\S]*?\?>"#, kind: .type),
                Rule(pattern: string, kind: .string),
                Rule(pattern: #"</?[A-Za-z][\w:.-]*"#, kind: .tag),
                Rule(pattern: #"[\w:.-]+(?=\s*=)"#, kind: .attribute),
                Rule(pattern: #"/?>"#, kind: .tag),
                Rule(pattern: #"&#?\w+;"#, kind: .variable),
            ]
        case .javascript:
            cLike(
                "var let const function return if else for while do switch case break continue new this class extends import export from default async await try catch finally throw typeof instanceof in of delete void yield true false null undefined",
                extra: [Rule(pattern: #"`(?:[^`\\]|\\.)*`"#, kind: .string)]
            )
        case .css:
            [
                Rule(pattern: #"/\*[\s\S]*?\*/"#, kind: .comment),
                Rule(pattern: string, kind: .string),
                Rule(pattern: #"@[\w-]+"#, kind: .keyword),
                Rule(pattern: #"#[0-9a-fA-F]{3,8}\b"#, kind: .number),
                Rule(pattern: #"-?\d*\.?\d+(?:px|em|rem|%|vh|vw|s|ms|deg)?\b"#, kind: .number),
                Rule(pattern: #"[\w-]+(?=\s*:[^{}]*[;}])"#, kind: .attribute),
                Rule(pattern: #"[.#][A-Za-z_][\w-]*|(?<![\w-])[a-z][a-z0-9]*(?=[^{}]*\{)"#, kind: .tag),
            ]
        case .graphql:
            [
                Rule(pattern: #"#[^\n]*"#, kind: .comment),
                Rule(pattern: #""""[\s\S]*?"""|"(?:[^"\\\n]|\\.)*""#, kind: .string),
                Rule(pattern: #"\$\w+"#, kind: .variable),
                Rule(pattern: words("query mutation subscription fragment on type input enum interface union scalar schema extend implements directive true false null"), kind: .keyword),
                Rule(pattern: #"@\w+"#, kind: .attribute),
                Rule(pattern: #"\b[A-Z]\w*\b"#, kind: .type),
                Rule(pattern: number, kind: .number),
            ]
        case .urlencoded:
            [Rule(pattern: #"^[^=&\n]+(?=\s*=)|(?<=&)[^=&\n]+(?==)"#, kind: .key, options: .anchorsMatchLines), Rule(pattern: #"(?<==)[^&\n]*"#, kind: .string)]
        case .http:
            [
                Rule(pattern: #"^(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|CONNECT|TRACE)\b"#, kind: .keyword, options: .anchorsMatchLines),
                Rule(pattern: #"HTTP/\d(?:\.\d)?"#, kind: .type),
                Rule(pattern: #"^[A-Za-z0-9_-]+(?=:)"#, kind: .key, options: .anchorsMatchLines),
                Rule(pattern: #"\b[1-5]\d\d\b"#, kind: .number),
            ]
        case .curl:
            [
                Rule(pattern: string, kind: .string),
                Rule(pattern: #"\bcurl\b"#, kind: .keyword),
                Rule(pattern: #"(?<=\s)--?[A-Za-z][\w-]*"#, kind: .attribute),
                Rule(pattern: #"https?://[^\s'"\\]+"#, kind: .type),
                Rule(pattern: #"\\$"#, kind: .comment, options: .anchorsMatchLines),
            ]
        case .swift:
            cLike("let var func class struct enum protocol extension import return if else guard switch case default for while in do try catch throw throws async await self nil true false init static private public final override where as is some any")
        case .python:
            cLike("def class import from as return if elif else for while in try except finally raise with lambda pass break continue None True False and or not is yield async await", comment: "#[^\\n]*")
        case .go:
            cLike("package import func return if else for range switch case default var const type struct interface map chan go defer select break continue nil true false")
        case .ruby:
            cLike("def end class module require return if elsif else unless while do begin rescue ensure yield nil true false self", comment: "#[^\\n]*")
        case .php:
            cLike(
                "function class return if else elseif foreach for while echo new public private static use namespace null true false array",
                comment: #"//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/"#,
                extra: [Rule(pattern: #"\$\w+"#, kind: .variable)]
            )
        case .protobuf, .plain, .binary:
            []
        }
    }

    private static let cache = NSCache<NSString, NSRegularExpression>()
    private static func compiled(_ rule: Rule) -> NSRegularExpression? {
        let key = "\(rule.options.rawValue)|\(rule.pattern)" as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { return nil }
        cache.setObject(regex, forKey: key)
        return regex
    }
}
