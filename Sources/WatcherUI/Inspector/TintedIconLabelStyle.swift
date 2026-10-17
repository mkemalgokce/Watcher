import SwiftUI

/// Coloured symbol, plain-coloured title.
struct TintedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon; configuration.title.foregroundStyle(.primary) }
    }
}
