import SwiftUI
import WatcherCore

struct PreviewsView: View {
    @Environment(AppModel.self) private var model
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
                                SyntaxTextView(output.text, language: BodyLanguage.detect(contentType: nil, data: Data(output.text.utf8))).frame(minHeight: 120)
                            }
                        }
                    }
                    .padding(Metrics.gutter)
                }
            } else {
                ProgressView("Running previewers…").controlSize(.small)
            }
        }
        .task(id: flow.id) { outputs = nil; outputs = await model.engine.previews(for: flow) }
    }
}
