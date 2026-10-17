import SwiftUI
import WatcherCore

/// Encode and decode snippets without leaving the app: paste, pick what to do, copy the result.
struct ConverterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var operation = Converter.Operation.base64Decode
    @State private var output = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Convert", selection: $operation) { ForEach(Converter.Operation.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 260)
                Spacer()
                // Only on request: reading the clipboard by itself shows a paste-permission prompt and can pick up private text.
                Button("Paste", systemImage: "doc.on.clipboard") { input = model.pasteboard.string(forType: .string) ?? input }
            }
            pane("Input") { SyntaxTextView(text: $input, language: .plain) }
            HStack {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.error).font(.callout)
                } else if !input.isEmpty {
                    Label("Converted", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.done).font(.callout)
                }
                Spacer()
                Button("Use Result as Input", systemImage: "arrow.up.arrow.down") { input = output }.disabled(output.isEmpty)
                Button("Copy Result", systemImage: "doc.on.doc") { model.copy(output, "Result copied") }.disabled(output.isEmpty)
            }
            pane("Result") { SyntaxTextView(output, language: BodyLanguage.detect(contentType: nil, data: Data(output.utf8))) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(16).frame(minWidth: 620, minHeight: 480)
        .onChange(of: input) { _, _ in run() }
        .onChange(of: operation) { _, _ in run() }
    }

    private func pane(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            content().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func run() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { output = ""; failure = nil; return }
        do { output = try Converter.run(operation, input); failure = nil } catch { output = ""; failure = "\(error)" }
    }
}
