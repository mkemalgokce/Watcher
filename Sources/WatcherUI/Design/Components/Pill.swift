import SwiftUI

/// A coloured capsule with short text, e.g. a status code or a tag.
struct Pill: View {
    let text: String
    var tint: Color = .secondary
    var monospaced = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: monospaced ? .monospaced : .default).monospacedDigit())
            .foregroundStyle(tint == .secondary ? Color.secondary : tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
