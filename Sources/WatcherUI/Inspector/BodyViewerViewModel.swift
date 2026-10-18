import Foundation
import Observation
import WatcherCore

/// The text and rendering facts of one side's body. Small bodies are ready at creation so the first frame shows them;
/// large ones are formatted off the main thread.
@MainActor @Observable
final class BodyViewerViewModel {
    typealias ProtobufText = @MainActor (Flow, MessageSide) -> String

    /// Bodies below this are formatted on the spot.
    static let instantLimit = 256 * 1024
    private static let typingPause = Duration.milliseconds(300)

    private(set) var prepared: BodyRendering.Prepared?
    private(set) var unpacked: BodyRendering.Unpacked?

    @ObservationIgnored private let protobufText: ProtobufText
    @ObservationIgnored private let sleep: Sleep

    init(
        flow: Flow, side: MessageSide, mode: BodyMode, sortKeys: Bool,
        protobufText: @escaping ProtobufText, sleep: @escaping Sleep
    ) {
        self.protobufText = protobufText
        self.sleep = sleep
        let payload = flow.body(side)
        guard payload.count < Self.instantLimit else { return }
        let textMode = mode == .preview ? .pretty : mode
        let headers = flow.headers(side)
        let result = BodyRendering.prepare(
            payload, contentType: headers.value(for: "content-type"), encoding: headers.value(for: "content-encoding"),
            mode: textMode, sortKeys: sortKeys
        )
        prepared = schemaApplied(to: result, flow: flow, side: side, mode: textMode)
        unpacked = BodyRendering.unpack(
            key(flow, side), payload, contentType: headers.value(for: "content-type"),
            encoding: headers.value(for: "content-encoding")
        )
    }

    /// The unpacked body, unless it is left over from another selection.
    func current(for flow: Flow, side: MessageSide) -> BodyRendering.Unpacked? {
        unpacked?.id == key(flow, side) ? unpacked : nil
    }

    func unpack(_ flow: Flow, side: MessageSide) async {
        guard current(for: flow, side: side) == nil else { return }
        let (key, payload) = (key(flow, side), flow.body(side))
        let headers = flow.headers(side)
        let (type, encoding) = (headers.value(for: "content-type"), headers.value(for: "content-encoding"))
        let unpack: @Sendable () -> BodyRendering.Unpacked = {
            BodyRendering.unpack(key, payload, contentType: type, encoding: encoding)
        }
        let result = payload.count < Self.instantLimit
            ? unpack() : await Task.detached(priority: .userInitiated, operation: unpack).value
        if !Task.isCancelled {
            unpacked = result
        }
    }

    /// Formats and filters; a newer call (another selection, a key typed) cancels this one by cancelling its task.
    func prepare(_ flow: Flow, side: MessageSide, mode: BodyMode, sortKeys: Bool, path: String) async {
        let payload = flow.body(side)
        let headers = flow.headers(side)
        let (type, encoding) = (headers.value(for: "content-type"), headers.value(for: "content-encoding"))
        let prepare: @Sendable () -> BodyRendering.Prepared = {
            BodyRendering.prepare(
                payload, contentType: type, encoding: encoding, mode: mode, sortKeys: sortKeys, path: path
            )
        }
        var result: BodyRendering.Prepared
        if payload.count < Self.instantLimit {
            result = prepare()
        } else {
            if !path.isEmpty {
                try? await sleep(Self.typingPause) // let typing settle before querying a large document
            }
            guard !Task.isCancelled else { return }
            result = await Task.detached(priority: .userInitiated, operation: prepare).value
        }
        guard !Task.isCancelled else { return }
        prepared = schemaApplied(to: result, flow: flow, side: side, mode: mode)
    }

    /// The complete text for copy and save, even when the viewer shows only the first part.
    func fullText(_ flow: Flow, side: MessageSide, mode: BodyMode, sortKeys: Bool) -> String {
        let headers = flow.headers(side)
        let result = BodyRendering.prepare(
            flow.body(side), contentType: headers.value(for: "content-type"),
            encoding: headers.value(for: "content-encoding"), mode: mode, sortKeys: sortKeys, limit: nil
        )
        return schemaApplied(to: result, flow: flow, side: side, mode: mode).text
    }

    private func key(_ flow: Flow, _ side: MessageSide) -> BodyRendering.UnpackKey {
        BodyRendering.UnpackKey(flow: flow.id, side: side, size: flow.body(side).count)
    }

    /// A protobuf body shows as the message its schema rule names, whole, so nothing of an earlier cut remains.
    private func schemaApplied(
        to result: BodyRendering.Prepared, flow: Flow, side: MessageSide, mode: BodyMode
    ) -> BodyRendering.Prepared {
        guard result.language == .protobuf, mode == .pretty else { return result }
        var described = result
        described.text = protobufText(flow, side)
        described.cutFrom = nil
        return described
    }
}
