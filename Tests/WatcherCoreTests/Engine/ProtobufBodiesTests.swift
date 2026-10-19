import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// The schema reload rules and the body fallback, without an engine.
@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct ProtobufBodiesTests {
    private let fake = FileAccessFake()
    private let reads = LockedBox(0)
    private let logged = LockedBox<[String]>([])
    private let path = "/fake-home/schema.desc"
    private let message = ProtobufBytes.user(named: "Ada")

    private var bodies: ProtobufBodies {
        var access = fake.access
        let read = access.read
        access.read = { [reads] url in
            reads.mutate { $0 += 1 }
            return try read(url)
        }
        return ProtobufBodies(files: access)
    }

    private func load(_ bodies: ProtobufBodies, _ paths: [String]) {
        bodies.load(paths) { [logged] line in logged.mutate { $0.append(line) } }
    }

    private func flow(contentType: String = "application/x-protobuf") -> Flow {
        .fixture(
            request: .fixture(headers: [Header("Content-Type", contentType)]),
            response: .fixture(headers: [Header("Content-Type", contentType)], body: message)
        )
    }

    private let rule = ProtobufRule(matching: MatchingRule(pattern: "*"), responseType: "demo.User")

    @Test
    func unchangedPathsDoNotReadTheFilesAgain() {
        fake.write(ProtobufBytes.userDescriptorSet, to: path)
        let bodies = bodies
        load(bodies, [path])
        load(bodies, [path])
        #expect(reads.value == 1)
    }

    @Test
    func changedPathsAreReadAgain() {
        fake.write(ProtobufBytes.userDescriptorSet, to: path)
        let bodies = bodies
        load(bodies, [path])
        load(bodies, [path, path])
        #expect(reads.value == 3)
    }

    @Test
    func aFailedFileIsRetriedAndLoggedEachTime() {
        let bodies = bodies
        load(bodies, [path])
        load(bodies, [path])
        #expect(reads.value == 2)
        #expect(logged.value.filter { $0.hasPrefix("Protobuf schema \(path)") }.count == 2)
    }

    @Test
    func unparsableSchemaBytesAreLogged() {
        fake.write(Data([0xFF, 0xFF, 0xFF]), to: path)
        load(bodies, [path])
        #expect(logged.value.contains("Protobuf schemas could not be parsed"))
    }

    @Test
    func noPathsLogNothing() {
        load(bodies, [])
        #expect(logged.value.isEmpty)
    }

    @Test
    func aBodyIsDecodedWhenARuleMatches() {
        fake.write(ProtobufBytes.userDescriptorSet, to: path)
        let bodies = bodies
        load(bodies, [path])
        #expect(bodies.text(of: flow(), response: true, rules: [rule]) == #"name: "Ada""#)
    }

    @Test
    func aBodyFallsBackToThePreviewWhenNoRuleMatches() {
        fake.write(ProtobufBytes.userDescriptorSet, to: path)
        let bodies = bodies
        load(bodies, [path])
        let expected = BodyPreview.text(message, contentType: "application/x-protobuf")
        #expect(bodies.text(of: flow(), response: true, rules: []) == expected)
    }

    @Test
    func aBodyFallsBackToThePreviewWithoutASchema() {
        let expected = BodyPreview.text(message, contentType: "application/x-protobuf")
        #expect(bodies.text(of: flow(), response: true, rules: [rule]) == expected)
    }
}
