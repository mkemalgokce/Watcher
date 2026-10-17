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

/// What every colour and symbol in the window means, so none of them has to be guessed.
struct Legend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Status") {
                row(Palette.status(200), "2xx", "Success")
                row(Palette.status(301), "3xx", "Redirect: the answer is elsewhere")
                row(Palette.status(404), "4xx", "Client error: bad request, not found, not allowed")
                row(Palette.status(500), "5xx", "Server error")
                row(Palette.status(nil, failed: true), "Failed", "No response at all: connection, DNS or TLS failed")
                row(Palette.pending, "…", "Waiting for the response")
            }
            section("Methods") {
                row(Palette.method("GET"), "GET · HEAD", "Read; safe to repeat")
                row(Palette.method("POST"), "POST", "Create or send")
                row(Palette.method("PUT"), "PUT · PATCH", "Change")
                row(Palette.method("DELETE"), "DELETE", "Remove")
            }
            section("Symbols") {
                symbol("arrow.up.circle.fill", Palette.request, "Request: what the app sent")
                symbol("arrow.down.circle.fill", Palette.response, "Response: what the server answered")
                symbol("lock.fill", .secondary, "HTTPS decrypted by Watcher")
                symbol("lock", .secondary, "HTTPS passed through encrypted (see SSL Proxying in Tools)")
                symbol("wrench.adjustable", Palette.modified, "Changed by a tool: Map Local, Scripting, Breakpoints…")
                symbol("pause.circle.fill", Palette.paused, "Paused at a breakpoint, waiting for you")
                symbol("star.fill", Palette.starred, "Starred by you (⌘D)")
                symbol("text.bubble", .secondary, "Has your comment")
            }
            section("Duration column") {
                HStack(spacing: 8) {
                    Capsule().fill(Color.accentColor.opacity(0.75)).frame(width: 40, height: 4).accessibilityHidden(true)
                    Text("Duration compared with the slowest request on screen; red when it failed.").font(.callout)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func row(_ color: Color, _ label: String, _ meaning: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.callout.monospaced().weight(.semibold)).foregroundStyle(color)
                .padding(.horizontal, 6).padding(.vertical, 1).background(color.opacity(0.14), in: Capsule())
                .frame(width: 120, alignment: .leading)
            Text(meaning).font(.callout)
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ name: String, _ color: Color, _ meaning: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: name).foregroundStyle(color).frame(width: 120, alignment: .leading).accessibilityHidden(true)
            Text(meaning).font(.callout)
        }
    }
}
