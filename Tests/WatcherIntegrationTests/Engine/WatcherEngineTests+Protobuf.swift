import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension WatcherEngineTests {
    /// Schema-decoded bodies: which rule applies, which side, gRPC framing, and a schema file that appears later.
    @Suite(.serialized)
    struct Protobuf {
        private let files = FileAccessFake()
        private let logged = LockedBox<[String]>([])
        private let schemaPath = "/fake-home/schema.desc"
        private let message = ProtobufBytes.user(named: "Ada")

        private func running(
            pattern: String = "*",
            requestType: String = "",
            responseType: String = "demo.User"
        ) async throws -> WatcherEngine {
            let engine = try WatcherEngine.inMemory(files: files)
            engine.onLog = { [logged] line in logged.mutate { $0.append(line) } }
            let rule = ProtobufRule(
                matching: MatchingRule(pattern: pattern), requestType: requestType, responseType: responseType
            )
            try engine.settings.update {
                $0.protobufSchemas = [schemaPath]
                $0.protobuf = RuleSet(isEnabled: true, rules: [rule])
            }
            try await engine.start(port: 0)
            return engine
        }

        private func flow(
            requestBody: Data = Data(),
            responseBody: Data,
            contentType: String = "application/x-protobuf"
        ) -> Flow {
            .fixture(
                request: .fixture(headers: [Header("Content-Type", contentType)], body: requestBody),
                response: .fixture(headers: [Header("Content-Type", contentType)], body: responseBody)
            )
        }

        @Test
        func aResponseIsDecodedWithTheTypeOfTheMatchingRule() async throws {
            files.write(ProtobufBytes.userDescriptorSet, to: schemaPath)
            let engine = try await running()
            #expect(engine.bodyText(of: flow(responseBody: message), response: true) == #"name: "Ada""#)
            try await engine.stop()
        }

        @Test
        func aSideWithoutATypeKeepsTheGenericPreview() async throws {
            files.write(ProtobufBytes.userDescriptorSet, to: schemaPath)
            let engine = try await running(requestType: "")
            let flow = flow(requestBody: message, responseBody: message)
            let expected = BodyPreview.text(message, contentType: "application/x-protobuf")
            #expect(engine.bodyText(of: flow, response: false) == expected)
            try await engine.stop()
        }

        @Test
        func aGRPCFrameHeaderIsStrippedBeforeDecoding() async throws {
            files.write(ProtobufBytes.userDescriptorSet, to: schemaPath)
            let engine = try await running()
            let framed = Data([0, 0, 0, 0, UInt8(message.count)]) + message
            let flow = flow(responseBody: framed, contentType: "application/grpc")
            #expect(engine.bodyText(of: flow, response: true) == #"name: "Ada""#)
            try await engine.stop()
        }

        @Test
        func theFrameHeaderIsKeptWhenTheContentTypeIsNotGRPC() async throws {
            files.write(ProtobufBytes.userDescriptorSet, to: schemaPath)
            let engine = try await running()
            let framed = Data([0, 0, 0, 0, UInt8(message.count)]) + message
            #expect(engine.bodyText(of: flow(responseBody: framed), response: true) != #"name: "Ada""#)
            try await engine.stop()
        }

        @Test
        func aRuleForAnotherURLLeavesTheGenericPreview() async throws {
            files.write(ProtobufBytes.userDescriptorSet, to: schemaPath)
            let engine = try await running(pattern: "other.test/*")
            let expected = BodyPreview.text(message, contentType: "application/x-protobuf")
            #expect(engine.bodyText(of: flow(responseBody: message), response: true) == expected)
            try await engine.stop()
        }

        @Test
        func aSchemaFileThatAppearsLaterIsPickedUpOnTheNextApply() async throws {
            let engine = try await running()
            let flow = flow(responseBody: message)
            #expect(engine.bodyText(of: flow, response: true) != #"name: "Ada""#)
            #expect(logged.value.contains { $0.hasPrefix("Protobuf schema \(schemaPath)") }, "\(logged.value)")
            files.write(ProtobufBytes.userDescriptorSet, to: schemaPath)
            await engine.apply(engine.settings.value)
            #expect(engine.bodyText(of: flow, response: true) == #"name: "Ada""#)
            try await engine.stop()
        }

        @Test
        func aSchemaFileThatFailedIsTriedAgainWhileTheOthersLoad() async throws {
            files.write(ProtobufBytes.userDescriptorSet, to: schemaPath)
            let engine = try await running()
            let missing = "/fake-home/missing.desc"
            var settings = engine.settings.value
            settings.protobufSchemas = [schemaPath, missing]
            await engine.apply(settings)
            await engine.apply(settings)
            let failures = logged.value.filter { $0.hasPrefix("Protobuf schema \(missing)") }
            #expect(failures.count == 2, "\(logged.value)")
            try await engine.stop()
        }
    }
}
