import Foundation
import WatcherCore

/// A highlighter token paired with the text it covers, so a test compares what a reader would see coloured.
public struct HighlightedSpan: Equatable, CustomStringConvertible {
    public let text: String
    public let kind: SyntaxHighlighter.Kind

    public init(_ text: String, _ kind: SyntaxHighlighter.Kind) {
        self.text = text
        self.kind = kind
    }

    public var description: String {
        "\(text) as \(kind)"
    }
}

public extension [SyntaxHighlighter.Token] {
    func spans(in text: String) -> [HighlightedSpan] {
        let utf16 = text as NSString
        return map { HighlightedSpan(utf16.substring(with: $0.range), $0.kind) }
    }
}
