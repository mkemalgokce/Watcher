import SwiftUI
import WatcherCore

/// Which requests a rule applies to: the pattern up front, the rarer conditions folded away.
struct RuleFields: View {
    @Binding var name: String
    @Binding var matching: MatchingRule
    @State private var showsMore = false

    var body: some View {
        Section {
            TextField("Name", text: $name, prompt: Text("Optional"))
            LabeledField(
                matching.mode == .regex ? "URL regex" : "URL pattern",
                prompt: "api.example.com/v1/*",
                text: $matching.pattern,
                help: matching.mode == .regex ? "Regular expression matched against the full URL." : "* matches any text, ? one character. The scheme is optional."
            )
            DisclosureGroup("More conditions", isExpanded: $showsMore) {
                Picker("Pattern type", selection: $matching.mode) {
                    Text("Wildcard").tag(MatchingRule.Mode.wildcard)
                    Text("Regex").tag(MatchingRule.Mode.regex)
                }
                Toggle("Include subpaths", isOn: $matching.includeSubpaths)
                LabeledField(
                    "Methods",
                    prompt: "GET, POST",
                    text: Binding(
                        get: { matching.methods.joined(separator: ", ") },
                        set: { matching.methods = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty } }
                    ),
                    help: "Empty matches every method."
                )
                LabeledField("App", prompt: "Google Chrome*", text: Binding(get: { matching.app ?? "" }, set: { matching.app = $0.isEmpty ? nil : $0 }))
                LabeledField("GraphQL operation", prompt: "GetUser", text: Binding(get: { matching.graphQLQueryName ?? "" }, set: { matching.graphQLQueryName = $0.isEmpty ? nil : $0 }))
            }
        } header: { Text("Applies to") }
            .onAppear { showsMore = matching.mode == .regex || !matching.methods.isEmpty || matching.app != nil || matching.graphQLQueryName != nil }
    }
}

/// A text field with an example as its prompt and, when it needs one, a line of help below.
struct LabeledField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var help: String?

    init(_ label: String, prompt: String, text: Binding<String>, help: String? = nil) {
        self.label = label; self.prompt = prompt; _text = text; self.help = help
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField(label, text: $text, prompt: Text(prompt))
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct OptionalText: View {
    let label: String
    let prompt: String
    @Binding var value: String?

    init(_ label: String, prompt: String, value: Binding<String?>) {
        self.label = label; self.prompt = prompt; _value = value
    }

    var body: some View {
        TextField(label, text: Binding(get: { value ?? "" }, set: { value = $0.isEmpty ? nil : $0 }), prompt: Text(prompt))
    }
}

/// Monospaced multi-line code with a visible label for VoiceOver.
struct CodeEditorField: View {
    @Binding var text: String
    let label: String
    var minHeight: CGFloat = 140

    var body: some View {
        TextEditor(text: $text).font(.system(.callout, design: .monospaced))
            .frame(minHeight: minHeight).scrollContentBackground(.hidden)
            .padding(4).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(label)
    }
}

struct MapLocalSourceFields: View {
    @Binding var source: MapLocalRule.Source
    @Environment(AppModel.self) private var model

    private var isDirectory: Bool {
        if case .directory = source {
            true
        } else {
            false
        }
    }

    private var path: String {
        switch source { case let .file(path), let .directory(path): path }
    }

    var body: some View {
        Picker("Source", selection: Binding(get: { isDirectory }, set: { source = $0 ? .directory(path) : .file(path) })) {
            Text("File").tag(false)
            Text("Directory").tag(true)
        }.pickerStyle(.segmented)
        HStack {
            LabeledField(
                isDirectory ? "Directory" : "File",
                prompt: isDirectory ? "~/mocks/api" : "~/mocks/users.json",
                text: Binding(get: { path }, set: { source = isDirectory ? .directory($0) : .file($0) }),
                help: isDirectory ? "The request path is looked up inside this directory." : "A body file, or a full HTTP message (status line, headers, blank line, body)."
            )
            Button("Choose…") { choose() }
        }
    }

    private func choose() {
        source = model.filePicker.chooseSource(directory: isDirectory) ?? source
    }
}

/// Comma-separated text for a list of host patterns.
func commaList(_ values: Binding<[String]>) -> Binding<String> {
    Binding(
        get: { values.wrappedValue.joined(separator: ", ") },
        set: { values.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    )
}
