import SwiftUI
import WatcherCore

/// Shown in the inspector header when the request carries a JWT: one click shows what is inside it.
struct JWTButton: View {
    let flow: Flow
    @State private var showing = false

    /// Only headers are searched: that is where tokens travel, and it keeps the header instant for large bodies.
    private var tokens: [JWT] {
        JWT.find(in: (flow.request.headers + (flow.response?.headers ?? [])).map { "\($0.name): \($0.value)" }.joined(separator: "\n"))
    }

    var body: some View {
        let tokens = tokens
        if !tokens.isEmpty {
            Button { showing.toggle() } label: {
                Label(tokens.count == 1 ? "JWT" : "\(tokens.count) JWTs", systemImage: "key.fill").font(.caption.weight(.semibold))
                    .foregroundStyle(tokens.contains { $0.isExpired() } ? Palette.error : Palette.modified)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background((tokens.contains { $0.isExpired() } ? Palette.error : Palette.modified).opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(tokens.contains { $0.isExpired() } ? "Carries an expired JSON Web Token. Click to decode it." : "Carries a JSON Web Token. Click to decode it.")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { ForEach(tokens, id: \.raw) { TokenView(token: $0) } }.padding(14)
                }
                .frame(width: 560, height: min(560, CGFloat(tokens.count) * 220 + 40))
            }
        }
    }
}

struct TokenView: View {
    let token: JWT

    private var status: (text: String, color: Color, icon: String)? {
        guard let expires = token.expiresAt else { return nil }
        let relative = RelativeDateTimeFormatter().localizedString(for: expires, relativeTo: Date())
        return token.isExpired() ? ("Expired \(relative)", .red, "xmark.circle.fill") : ("Expires \(relative)", .green, "checkmark.circle.fill")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Token", systemImage: "key").font(.subheadline.weight(.medium))
                if let status {
                    Label(status.text, systemImage: status.icon).font(.caption.weight(.medium)).foregroundStyle(status.color)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                SyntaxTextView(token.header, language: .json).frame(height: 110)
                SyntaxTextView(token.payload, language: .json).frame(height: 110)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            Text("The signature is not verified: Watcher does not have the key.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
