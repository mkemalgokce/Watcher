import SwiftUI
import WatcherCore

/// One JSON value with everything the body viewer offers: a tree or the text, a path or jq filter, sorted keys, copy.
struct JSONDocumentView: View {
    @Environment(RequestActions.self) private var actions
    @State private var model: JSONDocumentModel

    init(source: String) {
        _model = State(initialValue: JSONDocumentModel(source: source))
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            toolbar($model)
            if model.prepared.pathFailed {
                Label("This filter could not run, so all of it is shown.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Palette.warning)
            }
            content
        }
    }

    private func toolbar(_ model: Bindable<JSONDocumentModel>) -> some View {
        HStack(spacing: 6) {
            Picker("View as", selection: model.showsTree) {
                Label("Tree", systemImage: "list.bullet.indent").tag(true)
                Label("Text", systemImage: "text.alignleft").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            TextField("Filter: users[0].name, ..email, .items[] | .id", text: model.path)
                .textFieldStyle(.roundedBorder).controlSize(.small).accessibilityLabel("JSON path or jq filter")
            if self.model.showsTree, let tree = self.model.tree {
                JSONFoldButtons(model: tree)
            }
            IconButton("Copy", symbol: "doc.on.doc") { actions.copy(self.model.prepared.text, "JSON copied") }
            Menu {
                Toggle("Sort Keys", isOn: model.sortsKeys)
                Button("Copy as Minified JSON") { actions.copy(self.model.minified, "Minified JSON copied") }
            } label: {
                Image(systemName: "ellipsis").font(.iconGlyph)
                    .frame(width: Metrics.iconButton, height: Metrics.iconButton)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More JSON actions")
        }
    }

    @ViewBuilder private var content: some View {
        if model.hasNoMatch {
            ContentUnavailableView(
                "No Match", systemImage: "magnifyingglass",
                description: Text("The filter found nothing in this value.")
            )
        } else if model.showsTree, let tree = model.tree {
            JSONTreeView(model: tree).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        } else {
            SyntaxTextView(model.prepared.text, language: .json, wraps: true)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// An eye that opens a JSON value in a popover, for a field or message that holds JSON inside something else.
struct JSONPopoverButton: View {
    let source: String
    var title = "View as JSON"
    @State private var showing = false

    var body: some View {
        Button(title, systemImage: "eye") { showing = true }
            .labelStyle(.iconOnly).buttonStyle(.borderless).help(title)
            .popover(isPresented: $showing) {
                JSONDocumentView(source: source).frame(width: 520, height: 380).padding(10)
            }
    }
}
