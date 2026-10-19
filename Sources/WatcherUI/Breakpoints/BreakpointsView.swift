import SwiftUI
import WatcherCore

/// Requests and responses held by a Breakpoint rule: edit them and let them through, or abort them.
/// The rules themselves are listed beside them, so a breakpoint that keeps firing can be switched off or removed right here.
struct BreakpointsView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @Environment(BreakpointsViewModel.self) private var breakpoints
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, Metrics.gutter).padding(.vertical, 12)
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 250, idealWidth: 280, maxWidth: 360)
                detail.frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            selection = BreakpointsViewModel.selection(keeping: selection, among: breakpoints.hits.map(\.id))
        }
        .onChange(of: breakpoints.hits.map(\.id)) { _, ids in
            selection = BreakpointsViewModel.selection(keeping: selection, among: ids)
        }
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Image(systemName: breakpoints.hits.isEmpty ? "pause.circle" : "pause.circle.fill").font(.title2)
                .foregroundStyle(breakpoints.hits.isEmpty ? Color.secondary : Palette.paused)
            VStack(alignment: .leading, spacing: 2) {
                Text("Breakpoints").font(.headline)
                Text(breakpoints.hits.isEmpty ? "Nothing is waiting." : "\(breakpoints.hits.count) paused. The client waits until you continue or abort.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Breakpoints On", isOn: $model.settings.breakpoints.isEnabled).toggleStyle(.switch).controlSize(.small)
                .help("Turn every breakpoint off without deleting the rules")
            GlassGroup {
                HStack(spacing: 2) {
                    IconButton("Continue All", symbol: "play.fill") { breakpoints.continueAll() }
                        .disabled(breakpoints.hits.isEmpty)
                    IconButton("Abort All", symbol: "xmark.octagon", tint: breakpoints.hits.isEmpty ? nil : Palette.error) {
                        breakpoints.abortAll()
                    }
                    .disabled(breakpoints.hits.isEmpty)
                }
            }
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $selection) {
            Section("Paused") {
                if breakpoints.hits.isEmpty {
                    Text("No paused requests").foregroundStyle(.secondary)
                } else {
                    ForEach(breakpoints.hits) { hit in
                        HStack(spacing: 8) {
                            PhaseBadge(phase: hit.phase)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) { MethodBadge(method: hit.request.method); Text(hit.request.host).lineLimit(1) }
                                Text(hit.request.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, 2).tag(hit.id)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section {
                if model.settings.breakpoints.rules.isEmpty {
                    Text("No rules. Right-click a request and choose Add Breakpoint.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(model.settings.breakpoints.rules.enumerated()), id: \.offset) { index, rule in
                    RuleRow(rule: Binding(get: { rule }, set: { breakpoints.updateRule(at: index, to: $0) })) {
                        breakpoints.removeRule(rule, at: index)
                    }
                    .selectionDisabled()
                }
            } header: {
                HStack {
                    Text("Rules")
                    Spacer()
                    Button("Edit in Tools", systemImage: "slider.horizontal.3") {
                        router.toolsSelection = .breakpoint
                        router.show(.tools)
                    }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Edit match patterns in Tools ▸ Breakpoints")
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var detail: some View {
        if let hit = breakpoints.hits.first(where: { $0.id == selection }) ?? breakpoints.hits.first {
            HitEditor(hit: hit).id(hit.id)
        } else {
            ContentUnavailableView {
                Label("No Paused Requests", systemImage: "pause.circle")
            } description: {
                Text(model.settings.breakpoints.active.isEmpty
                    ? "No breakpoint is active. Right-click a request and choose Add Breakpoint for this URL."
                    : "Matching requests stop here so you can change them before they continue. You will be told when one arrives; this window does not open by itself.")
            }
        }
    }
}

/// One breakpoint rule: on/off, what it matches, delete.
private struct RuleRow: View {
    @Binding var rule: BreakpointRule
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Enabled", isOn: $rule.isEnabled).toggleStyle(.switch).controlSize(.mini).labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.displayName).lineLimit(1)
                if !rule.name.isEmpty {
                    Text(rule.matching.pattern).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .opacity(rule.isEnabled ? 1 : 0.5)
            .help("Stops the \(rule.phaseSummary)")
            Spacer(minLength: 4)
            IconButton("Delete Breakpoint", symbol: "trash", action: delete)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PhaseBadge: View {
    let phase: BreakpointCenter.Phase
    var body: some View {
        let isResponse = phase == .response
        Image(systemName: isResponse ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
            .foregroundStyle(isResponse ? Palette.response : Palette.request).imageScale(.large)
            .help(isResponse ? "Paused response" : "Paused request").accessibilityLabel(isResponse ? "Response" : "Request")
    }
}

private struct HitEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(BreakpointsViewModel.self) private var breakpoints
    @State private var viewModel: HitEditorViewModel

    init(hit: BreakpointCenter.Hit) {
        _viewModel = State(initialValue: HitEditorViewModel(hit: hit))
    }

    private var hit: BreakpointCenter.Hit {
        viewModel.hit
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(alignment: .leading, spacing: 10) {
            // The timeline only redraws this every second; the time itself comes from the app clock.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let wait = BreakpointsViewModel.wait(of: hit, at: model.now())
                Label(wait.text, systemImage: "hourglass")
                    .font(.caption).foregroundStyle(wait.isLate ? Palette.warning : Color.secondary)
            }
            if viewModel.isResponse {
                HStack {
                    Text("Status").font(.subheadline.weight(.medium))
                    TextField("200", text: $viewModel.status).frame(width: 70).font(.system(.body, design: .monospaced)).accessibilityLabel("Status code")
                    if let code = viewModel.statusCode {
                        Text(HTTPStatus.reason(code)).foregroundStyle(.secondary)
                    } else {
                        Label("Enter a code from 100 to 599", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Palette.error)
                    }
                    Spacer()
                    Menu("Use Template") {
                        ForEach(model.settings.allBreakpointTemplates, id: \.name) { template in Button(template.name) { viewModel.apply(template) } }
                    }.fixedSize()
                }
                Text(hit.request.url).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else {
                HStack {
                    Picker("Method", selection: $viewModel.method) { ForEach(ComposeViewModel.methods, id: \.self) { Text($0) } }
                        .labelsHidden().fixedSize().accessibilityLabel("Method")
                    TextField("URL", text: $viewModel.urlText).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced)).accessibilityLabel("URL")
                }
                if !viewModel.isURLValid {
                    Label("Enter a full URL, for example https://example.com/path", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Palette.error)
                }
            }
            VSplitView {
                ScrollView { KeyValueEditor(rows: $viewModel.headers, title: "Headers", suggestions: KeyValueEditor.commonHeaders).padding(.trailing, 4) }
                    .frame(minHeight: 110, idealHeight: 170)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Body").font(.subheadline.weight(.medium))
                        Text(viewModel.bodyLanguage.displayName).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if viewModel.bodyLanguage == .json {
                            IconButton("Beautify JSON", symbol: "text.alignleft") { viewModel.beautifyBody() }
                        }
                    }
                    SyntaxTextView(text: $viewModel.bodyText, language: viewModel.bodyLanguage)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius))
                }
                .padding(.top, 6).frame(minHeight: 140)
            }
            Text("⌘↩ send with your changes · ⇧⌘↩ continue unchanged · ⇧⌘⌫ abort").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Abort", systemImage: "xmark.octagon", role: .destructive) {
                    breakpoints.abort(hit)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift]).help("Fail this request (⇧⌘⌫)")
                Button("Remove Breakpoint", systemImage: "trash") { breakpoints.removeBreakpoints(for: hit) }
                    .help("Delete the rule that stopped this request and let it continue, so it stops pausing")
                    .disabled(breakpoints.rules(matching: hit.request).isEmpty)
                Spacer()
                Button("Continue Unchanged") {
                    breakpoints.continueUnchanged(hit)
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift]).help("Let the original through (⇧⌘↩)")
                Button("Execute Edited", systemImage: "play.fill") {
                    guard let resolution = viewModel.resolution() else { return }
                    breakpoints.execute(hit, with: resolution)
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                .disabled(!viewModel.canExecute).help("Send with your changes (⌘↩)")
            }
        }
        .padding(Metrics.gutter)
    }
}
