import SwiftUI

/// Every colour that carries meaning, in one place. The legend (⌘/ → Colours & Symbols) is drawn from these same values,
/// so what it explains is always what the window shows. System colours adapt to light, dark and Increase Contrast.
/// Colour is never the only signal: each use also has text, a symbol or a tooltip.
enum Palette {
    // Direction of a message.
    static let request = Color.blue
    static let response = Color.green

    // Outcome of an exchange.
    static let success = Color.green
    static let redirect = Color.blue
    static let clientError = Color.orange
    static let serverError = Color.red
    static let pending = Color.secondary

    // States and marks.
    static let error = Color.red
    static let warning = Color.orange
    static let done = Color.green
    static let modified = Color.purple
    static let starred = Color.yellow
    static let paused = Color.orange

    /// By HTTP status class; a request that never got a response counts as a server-side failure.
    static func status(_ code: Int?, failed: Bool = false) -> Color {
        if failed {
            return serverError
        }
        switch code ?? 0 {
        case 200 ..< 300: return success
        case 300 ..< 400: return redirect
        case 400 ..< 500: return clientError
        case 500 ..< 600: return serverError
        default: return pending
        }
    }

    /// Reads green-to-red from safe to destructive, so a DELETE stands out in a long list.
    static func method(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET", "HEAD", "OPTIONS": .blue
        case "POST": .green
        case "PUT", "PATCH": .orange
        case "DELETE": .red
        default: .secondary
        }
    }
}
