import Foundation

/// A `.keyboardShortcut(…)` written in Swift source, for tests that check the menus against each other and the docs.
public struct MenuShortcut: Equatable {
    /// The character between the quotes, or a named key such as `.delete`.
    public let key: String
    /// Sorted, such as `[".command", ".shift"]`; `[".command"]` when the source names none.
    public let modifiers: [String]

    public var isCharacter: Bool {
        !key.hasPrefix(".")
    }

    public static func all(in source: String) throws -> [MenuShortcut] {
        let pattern = try NSRegularExpression(
            pattern: #"\.keyboardShortcut\((?:"([^"]*)"|(\.\w+))(?:, modifiers: \[?([^)\]]*)\]?)?\)"#
        )
        return pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).map { match in
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: source).map { String(source[$0]) }
            }
            let modifiers = group(3)?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .sorted() ?? [".command"]
            return MenuShortcut(key: group(1) ?? group(2) ?? "", modifiers: modifiers)
        }
    }
}
