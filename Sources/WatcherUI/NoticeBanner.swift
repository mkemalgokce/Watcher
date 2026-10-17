import SwiftUI

/// Floating feedback for the last thing that happened. Uses Liquid Glass where the system has it and a material before that.
struct NoticeBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let notice = model.notice {
            HStack(spacing: 10) {
                Image(systemName: icon(notice.kind)).foregroundStyle(tint(notice.kind)).imageScale(.large).accessibilityHidden(true)
                Text(notice.message).font(.callout).lineLimit(3).textSelection(.enabled)
                if let action = notice.action {
                    Button(action.title) { action.perform() }.buttonStyle(.borderless).fontWeight(.semibold)
                }
                if notice.kind == .error {
                    Button("Dismiss", systemImage: "xmark") { model.dismissNotice() }.labelStyle(.iconOnly).buttonStyle(.plain).help("Dismiss")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .modifier(GlassBackground())
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain) // keeps Undo pressable on its own
            .accessibilityLabel("\(notice.kind == .error ? "Error: " : "")\(notice.message)")
            .id(notice.id)
        }
    }

    private func icon(_ kind: AppModel.Notice.Kind) -> String {
        switch kind { case .success: "checkmark.circle.fill"; case .info: "info.circle.fill"; case .error: "exclamationmark.triangle.fill" }
    }

    private func tint(_ kind: AppModel.Notice.Kind) -> Color {
        switch kind { case .success: .green; case .info: .accentColor; case .error: .red }
    }
}

/// Liquid Glass on macOS 26+, a blurred material with a hairline edge before that.
struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // A solid-enough base under the glass keeps text readable over dense tables.
            content.background(.thickMaterial, in: Capsule()).glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule()).overlay(Capsule().strokeBorder(.separator))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
    }
}
