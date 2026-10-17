import Foundation
import Observation
import WatcherCore

/// Compares two exchanges off the main thread; the Diff tab only draws the result.
@MainActor @Observable
final class DiffViewModel {
    enum Subject: String, CaseIterable, Identifiable {
        case responseBody = "Response Body", requestBody = "Request Body", headers = "Headers"
        var id: Self {
            self
        }
    }

    enum Layout: String, CaseIterable, Identifiable {
        case inline = "Inline", sideBySide = "Side by Side"
        var id: Self {
            self
        }
    }

    struct Result: Equatable {
        let lines: [TextDiff.Line]
        let rows: [TextDiff.Row]
        let added: Int
        let removed: Int
        var isIdentical: Bool {
            added == 0 && removed == 0
        }
    }

    enum State: Equatable {
        case noBase
        case sameFlow
        case computing
        case ready(Result)
    }

    var subject = Subject.responseBody
    var layout = Layout.inline
    private(set) var state = State.noBase

    /// What the shown state was computed from; a newer request makes an older result arrive stale and be dropped.
    @ObservationIgnored private var lastKey: Key?

    private struct Key: Equatable {
        let base: Flow.ID, current: Flow.ID, subject: Subject
        let baseSize: Int, currentSize: Int
    }

    /// Recomputes only when the pair, the subject or a body changed.
    func update(base: Flow?, current: Flow) async {
        guard let base else { lastKey = nil; state = .noBase; return }
        guard base.id != current.id else { lastKey = nil; state = .sameFlow; return }
        let key = Key(
            base: base.id,
            current: current.id,
            subject: subject,
            baseSize: Self.text(base, subject).utf8.count,
            currentSize: Self.text(current, subject).utf8.count
        )
        guard key != lastKey else { return }
        lastKey = key
        state = .computing
        let old = Self.text(base, subject), new = Self.text(current, subject)
        let result = await Task.detached(priority: .userInitiated) { Self.compare(old, new) }.value
        guard lastKey == key else { return }
        state = .ready(result)
    }

    nonisolated static func compare(_ old: String, _ new: String) -> Result {
        let lines = TextDiff.lines(from: old, to: new)
        return Result(
            lines: lines,
            rows: TextDiff.sideBySide(lines),
            added: lines.count(where: { $0.kind == .added }),
            removed: lines.count(where: { $0.kind == .removed })
        )
    }

    static func text(_ flow: Flow, _ subject: Subject) -> String {
        switch subject {
        case .responseBody: flow.response.map { BodyPreview.text($0.body, contentType: $0.headers.value(for: "content-type")) } ?? ""
        case .requestBody: BodyPreview.text(flow.request.body, contentType: flow.request.headers.value(for: "content-type"))
        case .headers:
            (["\(flow.request.method) \(flow.request.url)"] + flow.request.headers.map { "\($0.name): \($0.value)" }
                + ["", "HTTP \(flow.response?.status ?? 0)"] + (flow.response?.headers ?? []).map { "\($0.name): \($0.value)" }).joined(separator: "\n")
        }
    }

    /// The earlier call to the same endpoint: the base people almost always want.
    static func suggestedBase(for flow: Flow, in flows: [Flow]) -> Flow? {
        let path = flow.request.path.split(separator: "?", maxSplits: 1).first
        return flows.last { $0.sequence < flow.sequence && $0.request.method == flow.request.method && $0.request.host == flow.request.host
            && $0.request.path.split(separator: "?", maxSplits: 1).first == path
        }
    }
}
