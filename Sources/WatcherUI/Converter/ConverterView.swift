import SwiftUI
import WatcherCore

/// Encode and decode snippets without leaving the app: paste, pick what to do, copy the result.
struct ConverterView: View {
    @Environment(AppModel.self) private var model
    @Environment(RequestActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @State private var converter: ConverterViewModel

    init() {
        self.init(converter: ConverterViewModel())
    }

    init(converter: ConverterViewModel) {
        _converter = State(initialValue: converter)
    }

    var body: some View {
        @Bindable var converter = converter
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Convert", selection: $converter.operation) {
                    ForEach(Converter.Operation.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 260)
                Spacer()
                Button("Paste", systemImage: "doc.on.clipboard") { converter.paste(from: model.clipboard) }
            }
            pane("Input") { SyntaxTextView(text: $converter.input, language: .plain) }
            HStack {
                if let failure = converter.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.error).font(.callout)
                } else if converter.isConverted {
                    Label("Converted", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.done).font(.callout)
                }
                Spacer()
                Button("Use Result as Input", systemImage: "arrow.up.arrow.down") { converter.useResultAsInput() }
                    .disabled(converter.output.isEmpty)
                Button("Copy Result", systemImage: "doc.on.doc") { actions.copy(converter.output, "Result copied") }
                    .disabled(converter.output.isEmpty)
            }
            pane("Result") {
                SyntaxTextView(
                    converter.output,
                    language: BodyLanguage.detect(contentType: nil, data: Data(converter.output.utf8))
                )
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(16).frame(minWidth: 620, minHeight: 480)
    }

    private func pane(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            content().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
