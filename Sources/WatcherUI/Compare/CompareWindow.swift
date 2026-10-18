import SwiftUI
import WatcherCore

/// Its own window, so comparing never squeezes the inspector: the base stays put while the list selection is compared with it.
public struct CompareWindow: View {
    @Environment(WindowRouter.self) private var router
    @Environment(FlowListViewModel.self) private var list

    public init() {}

    public var body: some View {
        Group {
            if let current = list.selectedFlow {
                DiffView(current: current)
            } else {
                ContentUnavailableView(
                    "No Request Selected",
                    systemImage: "sidebar.right",
                    description: Text("Select a request in the main window to compare it with the base.")
                )
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle("Compare")
        .navigationSubtitle(router.diffBase.map { "Base #\($0.sequence) \($0.request.method) \($0.request.path)" } ?? "No base")
    }
}

struct DiffView: View {
    @Environment(WindowRouter.self) private var router
    @Environment(FlowListViewModel.self) private var list
    let current: Flow
    @State private var viewModel = DiffViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(alignment: .leading, spacing: 0) {
            if let base = router.diffBase, base.id != current.id {
                header(base: base, viewModel: viewModel).padding(Metrics.gutter)
                Divider()
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: TaskKey(base: router.diffBase?.id, current: current.id, size: current.response?.body.count, subject: viewModel.subject)) {
            await viewModel.update(base: router.diffBase, current: current)
        }
    }

    private struct TaskKey: Equatable { let base: Flow.ID?, current: Flow.ID, size: Int?, subject: DiffViewModel.Subject }

    private func header(base: Flow, viewModel: DiffViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FlowTag(flow: base, role: "Base")
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                FlowTag(flow: current, role: "This")
                Spacer()
                if case let .ready(result) = viewModel.state, !result.isIdentical {
                    Pill(text: "+\(result.added)", tint: .green, monospaced: true)
                    Pill(text: "−\(result.removed)", tint: .red, monospaced: true)
                }
                Menu {
                    if let suggested = DiffViewModel.suggestedBase(for: current, in: list.flows), suggested.id != base.id {
                        Button("Earlier Call to This Endpoint (#\(suggested.sequence))") { router.diffBase = suggested }
                    }
                    Button("Use This Request as Base") { router.diffBase = current }
                    Divider()
                    Button("Stop Comparing", role: .destructive) { router.diffBase = nil }
                } label: { Label("Base", systemImage: "arrow.left.arrow.right") }
                    .menuStyle(.borderlessButton).fixedSize().help("Change what this request is compared with")
            }
            HStack {
                Picker("Compare", selection: $viewModel.subject) { ForEach(DiffViewModel.Subject.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                Picker("Layout", selection: $viewModel.layout) { ForEach(DiffViewModel.Layout.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .noBase:
            let suggested = DiffViewModel.suggestedBase(for: current, in: list.flows)
            ContentUnavailableView {
                Label("Nothing to Compare With", systemImage: "arrow.left.arrow.right")
            } description: {
                Text(suggested == nil ? "Right-click a request in the list and choose Set as Compare Base (⇧⌘B)." : "Compare with the earlier call to the same endpoint, or right-click any request and choose Set as Compare Base (⇧⌘B).")
            } actions: {
                if let suggested {
                    Button("Compare with #\(suggested.sequence)") { router.diffBase = suggested }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .sameFlow:
            ContentUnavailableView(
                "This Is the Base",
                systemImage: "pin",
                description: Text("Select another request in the main window to see how it differs from #\(current.sequence).")
            )
        case .computing:
            ProgressView("Comparing…").controlSize(.small)
        case let .ready(result) where result.isIdentical:
            ContentUnavailableView(
                "No Differences",
                systemImage: "checkmark.circle",
                description: Text("The \(viewModel.subject.rawValue.lowercased()) of both requests is the same.")
            )
        case let .ready(result):
            switch viewModel.layout {
            case .inline: InlineDiff(lines: result.lines)
            case .sideBySide: SideBySideDiff(rows: result.rows)
            }
        }
    }
}

/// "#12 GET /path" with a role label.
private struct FlowTag: View {
    let flow: Flow, role: String
    var body: some View {
        HStack(spacing: 5) {
            Text(role).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text("#\(flow.sequence)").font(.caption.monospacedDigit().weight(.semibold))
            Text(flow.request.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).frame(maxWidth: 180, alignment: .leading)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.background.secondary, in: Capsule())
        .help("\(flow.request.method) \(flow.request.url)")
    }
}

private enum DiffStyle {
    static func background(_ kind: TextDiff.Line.Kind) -> Color {
        switch kind { case .same: .clear; case .added: .green.opacity(0.16); case .removed: .red.opacity(0.16) }
    }

    static func marker(_ kind: TextDiff.Line.Kind) -> String {
        switch kind { case .same: " "; case .added: "+"; case .removed: "−" }
    }

    static func markerColor(_ kind: TextDiff.Line.Kind) -> Color {
        switch kind { case .same: .secondary; case .added: .green; case .removed: .red }
    }
}

/// One column with line numbers; only the rows on screen are built, so long bodies scroll smoothly.
private struct InlineDiff: View {
    let lines: [TextDiff.Line]

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(spacing: 0) {
                        Text("\(index + 1)").foregroundStyle(.tertiary).frame(width: 44, alignment: .trailing).padding(.trailing, 6)
                        Text(DiffStyle.marker(line.kind)).foregroundStyle(DiffStyle.markerColor(line.kind)).frame(width: 14)
                        Text(line.text.isEmpty ? " " : line.text).textSelection(.enabled).fixedSize()
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.vertical, 1)
                    .background(DiffStyle.background(line.kind))
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct SideBySideDiff: View {
    let rows: [TextDiff.Row]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        cell(row.left)
                        Divider()
                        cell(row.right)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func cell(_ line: TextDiff.Line?) -> some View {
        HStack(spacing: 0) {
            Text(line.map { DiffStyle.marker($0.kind) } ?? " ").foregroundStyle(line.map { DiffStyle.markerColor($0.kind) } ?? .clear).frame(width: 14)
            Text(line?.text ?? " ").lineLimit(1).truncationMode(.tail).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.map { DiffStyle.background($0.kind) } ?? Color.secondary.opacity(0.04))
    }
}
