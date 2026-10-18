import SwiftUI
import WatcherCore

/// Title, what the tool does, and its master switch.
struct ToolHeader<Accessory: View>: View {
    let tool: ToolsView.Tool
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tool.icon).font(.title2).foregroundStyle(.tint).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.rawValue).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                // No fixedSize(vertical:) here: inside the split view's detail it sends layout into a loop and the whole window draws blank.
                Text(tool.explanation).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560, alignment: .leading)
            Spacer(minLength: 8)
            accessory
        }
        .padding(16)
    }
}

extension ToolHeader where Accessory == AnyView {
    init(tool: ToolsView.Tool, isOn: Binding<Bool>) {
        self.tool = tool
        accessory = AnyView(Toggle("Turn \(tool.rawValue) on", isOn: isOn).toggleStyle(.switch).labelsHidden()
            .help(isOn.wrappedValue ? "On: rules below take effect" : "Off: rules are kept but do nothing"))
    }
}

/// Master switch, a compact list of rules on the left and the selected rule's fields on the right.
struct RuleListEditor<Rule: ToolRule, Row: View>: View {
    let tool: ToolsView.Tool
    @Binding var set: RuleSet<Rule>
    /// One line that identifies a rule in the list.
    let title: (Rule) -> String
    let make: () -> Rule
    /// What is wrong with a rule (see ToolValidation); shown above its form and as a mark in the list.
    let problems: (Int) -> [String]
    @ViewBuilder let row: (Binding<Rule>) -> Row
    @State private var selection: Int?

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(tool: tool, isOn: $set.isEnabled)
            if !set.isEnabled, !set.rules.isEmpty {
                HStack {
                    Label("\(tool.rawValue) is off, so these rules do nothing.", systemImage: "pause.circle")
                        .font(.callout).foregroundStyle(Palette.warning)
                    Spacer()
                    Button("Turn On") { set.isEnabled = true }.controlSize(.small)
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            Divider()
            if set.rules.isEmpty {
                ContentUnavailableView {
                    Label("No rules yet", systemImage: tool.icon)
                } description: {
                    Text("Add a rule, or right-click a request in the list for a shortcut.")
                } actions: {
                    Button("Add Rule") { add() }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A fixed list beside a flexible form: HSplitView would split the space in half and push the form out of a narrow window.
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        List(selection: $selection) {
                            ForEach(set.rules.indices, id: \.self) { index in
                                ruleRow(index).tag(index)
                            }
                        }
                        .onDeleteCommand { removeSelected() }
                        Divider()
                        bottomBar
                    }
                    .frame(width: 220)
                    Divider()
                    Group {
                        if let selection, set.rules.indices.contains(selection) {
                            Form {
                                let issues = problems(selection)
                                if !issues.isEmpty {
                                    Section {
                                        ForEach(issues, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning) }
                                    }
                                }
                                row($set.rules[selection])
                                Section {
                                    TextField("Folder", text: Binding(
                                        get: { set.rules[selection].folder ?? "" },
                                        set: { set.rules[selection].folder = $0.isEmpty ? nil : $0 }
                                    ), prompt: Text("Optional"))
                                } footer: { Text("Rules in one folder can be switched on or off together.") }
                            }
                            .formStyle(.grouped)
                        } else {
                            ContentUnavailableView("Select a rule", systemImage: "sidebar.left", description: Text("Pick a rule on the left to edit it."))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if selection == nil, !set.rules.isEmpty {
                selection = 0
            }
        }
    }

    private func ruleRow(_ index: Int) -> some View {
        let rule = set.rules[index]
        return HStack(spacing: 8) {
            // Bounds-checked: a row drawn just before a delete must not write to an index that is gone.
            Toggle("Enabled", isOn: Binding(get: { rule.isEnabled }, set: {
                on in if set.rules.indices.contains(index) {
                    set.rules[index].isEnabled = on
                }
            }))
            .toggleStyle(.checkbox).labelsHidden()
            .accessibilityLabel("Enable \(title(rule))")
            VStack(alignment: .leading, spacing: 1) {
                Text(title(rule)).lineLimit(1).truncationMode(.middle).foregroundStyle(rule.isEnabled ? .primary : .secondary)
                if let folder = rule.folder {
                    Label(folder, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !problems(index).isEmpty {
                Spacer(minLength: 0)
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning).font(.caption)
                    .help(problems(index).joined(separator: "\n")).accessibilityLabel("Needs attention")
            }
        }
        .contextMenu {
            Button("Duplicate") { selection = set.duplicate(at: index) }
            Button("Delete", role: .destructive) { selection = set.remove(at: index) }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 2) {
            Button("Add Rule", systemImage: "plus") { add() }.help("Add a rule")
            Button("Remove Rule", systemImage: "minus") { removeSelected() }.disabled(selection == nil).help("Remove the selected rule (⌫)")
            Spacer()
            if !set.folders.isEmpty {
                Menu("Folders", systemImage: "folder") {
                    ForEach(set.folders, id: \.self) { name in
                        Section(name) {
                            Button("Enable All in \(name)") { set.setFolder(name, enabled: true) }
                            Button("Disable All in \(name)") { set.setFolder(name, enabled: false) }
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize().help("Switch a whole folder of rules on or off")
            }
        }
        .labelStyle(.iconOnly).buttonStyle(.borderless).padding(6)
    }

    private func add() {
        selection = set.add(make())
    }

    private func removeSelected() {
        guard let selection else { return }
        self.selection = set.remove(at: selection)
    }
}
