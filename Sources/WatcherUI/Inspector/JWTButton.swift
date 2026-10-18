import SwiftUI
import WatcherCore

/// Shown in the inspector header when the request carries a JWT: one click shows what is inside it.
struct JWTButton: View {
    let summary: JWTSummary
    @State private var showing = false

    var body: some View {
        let tokens = summary.tokens
        if !tokens.isEmpty {
            let tint = summary.anyExpired ? Palette.error : Palette.modified
            Button { showing.toggle() } label: {
                Label(summary.title, systemImage: "key.fill").font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(tint.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(summary.help)
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(tokens, id: \.raw) { TokenView(token: $0, expiry: summary.expiry(of: $0)) }
                    }
                    .padding(14)
                }
                .frame(width: 560, height: min(560, CGFloat(tokens.count) * 220 + 40))
            }
        }
    }
}

struct TokenView: View {
    let token: JWT
    let expiry: (text: String, isExpired: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Token", systemImage: "key").font(.subheadline.weight(.medium))
                if let expiry {
                    Label(expiry.text, systemImage: expiry.isExpired ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(expiry.isExpired ? .red : .green)
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
