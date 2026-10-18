import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@MainActor
@Suite(.tags(.unit))
struct BodyViewerViewModelTests {
    private let schemaText = "message Order { id: 1 }"

    private func flow(
        _ body: Data, type: String = "application/json", encoding: String? = nil, side: MessageSide = .response
    ) -> Flow {
        var headers = [Header("Content-Type", type)]
        if let encoding {
            headers.append(Header("Content-Encoding", encoding))
        }
        return side == .response
            ? .fixture(response: .fixture(headers: headers, body: body))
            : .fixture(request: .fixture(headers: headers, body: body))
    }

    private func model(
        _ flow: Flow, side: MessageSide = .response, mode: BodyMode = .pretty, sleep: @escaping Sleep = { _ in }
    ) -> BodyViewerViewModel {
        BodyViewerViewModel(
            flow: flow, side: side, mode: mode, sortKeys: false, protobufText: { [schemaText] _, _ in schemaText },
            sleep: sleep
        )
    }

    private func large(_ type: String = "text/plain") -> Flow {
        flow(Data(repeating: UInt8(ascii: "a"), count: BodyViewerViewModel.instantLimit + 1), type: type)
    }

    @Test
    func aSmallBodyIsReadyBeforeAnyTaskRuns() {
        let model = model(flow(Data(#"{"a":1}"#.utf8)))
        #expect(model.prepared?.language == .json)
        #expect(model.unpacked != nil)
    }

    @Test
    func aLargeBodyIsNotPreparedOnTheSpot() {
        let model = model(large())
        #expect(model.prepared == nil)
        #expect(model.unpacked == nil)
    }

    @Test
    func theBodyJustUnderTheLimitIsInstantAndOneAtTheLimitIsNot() {
        let under = flow(Data(repeating: 97, count: BodyViewerViewModel.instantLimit - 1), type: "text/plain")
        let over = flow(Data(repeating: 97, count: BodyViewerViewModel.instantLimit), type: "text/plain")
        #expect(model(under).prepared != nil)
        #expect(model(over).prepared == nil)
    }

    @Test
    func aPreviewRequestIsPreparedAsPrettyText() {
        let model = model(flow(Data(#"{"a":1}"#.utf8)), mode: .preview)
        #expect(model.prepared?.note != "raw")
    }

    @Test
    func aLargeBodyIsPreparedOffTheMainThreadAndCutForDisplay() async {
        let flow = flow(Data(repeating: 97, count: BodyRendering.displayLimit + 1), type: "text/plain")
        let model = model(flow)
        await model.prepare(flow, side: .response, mode: .pretty, sortKeys: false, path: "")
        #expect(model.prepared?.cutFrom == BodyRendering.displayLimit + 1)
    }

    @Test
    func aPathOnALargeBodyWaitsForTypingToSettle() async {
        let gate = SleepGate()
        let flow = large("application/json")
        let model = model(flow, sleep: gate.sleep)
        let preparing = Task { await model.prepare(flow, side: .response, mode: .pretty, sortKeys: false, path: "a") }
        #expect(await eventually { gate.waitingCount == 1 })
        #expect(model.prepared == nil)
        #expect(gate.durations == [.milliseconds(300)])
        gate.releaseOldest()
        await preparing.value
        #expect(model.prepared != nil)
    }

    @Test
    func noPathMeansNoWaitOnALargeBody() async {
        let gate = SleepGate()
        let flow = large()
        let model = model(flow, sleep: gate.sleep)
        await model.prepare(flow, side: .response, mode: .pretty, sortKeys: false, path: "")
        #expect(gate.durations.isEmpty)
        #expect(model.prepared != nil)
    }

    @Test
    func aCancelledPreparationLeavesTheLastResult() async {
        let gate = SleepGate()
        let flow = large("application/json")
        let model = model(flow, sleep: gate.sleep)
        let preparing = Task { await model.prepare(flow, side: .response, mode: .pretty, sortKeys: false, path: "a") }
        #expect(await eventually { gate.waitingCount == 1 })
        preparing.cancel()
        gate.releaseOldest()
        await preparing.value
        #expect(model.prepared == nil)
    }

    @Test
    func unpackingIsSkippedWhenTheBodyIsAlreadyUnpacked() async {
        let flow = flow(Data("hi".utf8), type: "text/plain")
        let model = model(flow)
        let before = model.unpacked
        await model.unpack(flow, side: .response)
        #expect(model.unpacked == before)
    }

    @Test
    func anotherSelectionsUnpackedBodyIsNotCurrent() async {
        let first = flow(Data("one".utf8), type: "text/plain")
        let second = flow(Data("two!".utf8), type: "text/plain")
        let model = model(first)
        #expect(model.current(for: second, side: .response) == nil)
        await model.unpack(second, side: .response)
        #expect(model.current(for: second, side: .response)?.data == Data("two!".utf8))
    }

    @Test
    func aGzipBodyIsUnpacked() async {
        let text = Data(repeating: UInt8(ascii: "a"), count: BodyViewerViewModel.instantLimit + 1)
        let flow = flow(text.gzipped, type: "text/plain", encoding: "gzip")
        let model = model(flow)
        await model.unpack(flow, side: .response)
        #expect(model.current(for: flow, side: .response)?.data == text)
    }

    @Test
    func aProtobufBodyShowsItsSchemaTextFromTheFirstFrame() {
        let flow = flow(Data([0x08, 0x01]), type: "application/x-protobuf")
        #expect(model(flow).prepared?.text == schemaText)
    }

    @Test
    func aProtobufBodyShowsItsSchemaTextAfterPreparing() async {
        let flow = flow(Data([0x08, 0x01]), type: "application/x-protobuf")
        let model = model(flow)
        await model.prepare(flow, side: .response, mode: .pretty, sortKeys: false, path: "")
        #expect(model.prepared?.text == schemaText)
    }

    @Test
    func aLargeProtobufBodyShowsItsSchemaTextWithoutAStaleCut() async {
        let flow = flow(Data(repeating: 97, count: BodyRendering.displayLimit + 1), type: "application/x-protobuf")
        let model = model(flow)
        await model.prepare(flow, side: .response, mode: .pretty, sortKeys: false, path: "")
        #expect(model.prepared?.text == schemaText)
        #expect(model.prepared?.cutFrom == nil)
    }

    @Test(arguments: [BodyMode.raw, .hex])
    func otherModesShowTheBytesNotTheSchema(mode: BodyMode) async {
        let flow = flow(Data([0x08, 0x01]), type: "application/x-protobuf")
        let model = model(flow, mode: mode)
        await model.prepare(flow, side: .response, mode: mode, sortKeys: false, path: "")
        #expect(model.prepared?.text != schemaText)
    }

    @Test
    func copyingAProtobufBodyCopiesWhatIsShown() {
        let flow = flow(Data([0x08, 0x01]), type: "application/x-protobuf")
        #expect(model(flow).fullText(flow, side: .response, mode: .pretty, sortKeys: false) == schemaText)
    }

    @Test
    func copyingGivesTheWholeBodyEvenWhenTheViewIsCut() {
        let flow = large()
        let text = model(flow).fullText(flow, side: .response, mode: .pretty, sortKeys: false)
        #expect(text.utf8.count == BodyViewerViewModel.instantLimit + 1)
    }

    @Test
    func theRequestSideReadsTheRequestBody() {
        let flow = flow(Data(#"{"q":1}"#.utf8), side: .request)
        #expect(model(flow, side: .request).prepared?.language == .json)
    }
}
