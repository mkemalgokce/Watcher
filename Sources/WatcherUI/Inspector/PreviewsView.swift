import SwiftUI
import WatcherCore

struct PreviewsView: View {
    @Environment(RequestActions.self) private var actions
    let flow: Flow
    @State private var outputs: [PreviewOutput]?

    var body: some View {
        Group {
            if let outputs, outputs.isEmpty {
                ContentUnavailableView(
                    "No Previewer Matches",
                    systemImage: "eye.slash",
                    description: Text("Add or change previewers in Tools ▸ Previewers.")
                )
            } else if let outputs {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.gutter) {
                        ForEach(Array(outputs.enumerated()), id: \.offset) { _, output in
                            Card(output.name, symbol: "eye") {
                                if JSONTree.isDocument(output.text) {
                                    JSONDocumentView(source: output.text).frame(height: 260)
                                } else {
                                    let language = BodyLanguage.detect(contentType: nil, data: Data(output.text.utf8))
                                    SyntaxTextView(output.text, language: language).frame(minHeight: 120)
                                }
                            }
                        }
                    }
                    .padding(Metrics.gutter)
                }
            } else {
                ProgressView("Running previewers…").controlSize(.small)
            }
        }
        .task(id: flow.id) { outputs = nil; outputs = await actions.previews(for: flow) }
    }
}
