import SwiftUI

/// Liquid Glass on macOS 26 and later; a quiet material with a hairline edge before that.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var interactive = false
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let glass = Glass.regular.tint(tint)
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            content
                .background((tint ?? .clear).opacity(0.18), in: shape)
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        }
    }
}

extension View {
    func glassSurface(_ shape: some InsettableShape, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: shape, interactive: interactive, tint: tint))
    }
}
