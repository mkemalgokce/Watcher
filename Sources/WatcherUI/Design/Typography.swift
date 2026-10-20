import SwiftUI

/// The monospaced face for code, keys and values, and the size of a lone glyph button, so views name a role
/// instead of building a font in place.
extension Font {
    static func code(_ style: Font.TextStyle) -> Font {
        .system(style, design: .monospaced)
    }

    static func code(size: Double, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// The glyph in a borderless icon-sized menu or button, as `IconButton` draws its own.
    static var iconGlyph: Font {
        .system(size: 15, weight: .regular)
    }
}
