import SwiftUI

/// Text for a list of values, one `separator` between them: each is trimmed, `transform`ed and kept only if not empty.
func listText(
    _ values: Binding<[String]>,
    separator: Character = ",",
    transform: @escaping (String) -> String = { $0 }
) -> Binding<String> {
    Binding(
        get: { values.wrappedValue.joined(separator: separator == "," ? ", " : String(separator)) },
        set: { values.wrappedValue = ListText.items($0, separator: separator, transform: transform) }
    )
}

/// The values a separated text holds.
enum ListText {
    static func items(_ text: String, separator: Character, transform: (String) -> String = { $0 }) -> [String] {
        text.split(separator: separator)
            .map { transform($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }
}
