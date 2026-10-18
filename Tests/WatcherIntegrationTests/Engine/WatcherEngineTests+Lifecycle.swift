import Foundation
import NIO
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension WatcherEngineTests {
    /// Engines on an in-memory file system with a fast reload clock; only the listening sockets are real.
    @Suite(.serialized)
    struct Lifecycle {
        private let files = FileAccessFake()
        private let logged = LockedBox<[String]>([])

        private func engine(
            pacLoader: @escaping @Sendable (String) async throws -> PACEvaluator = { _ in
                throw PACEvaluator.LoadError(description: "no PAC in this test")
            }
        ) throws -> WatcherEngine {
            let engine = try WatcherEngine(
                directory: URL(fileURLWithPath: "/fake-home/.watcher"),
                files: files.access,
                pacLoader: pacLoader,
                sleep: { _ in try await Task.sleep(for: .milliseconds(5)) },
                makeServer: { ProxyServer(store: $0, authority: $1, clientApp: { _ in nil }) }
            )
            engine.onLog = { [logged] line in logged.mutate { $0.append(line) } }
            return engine
        }

        @Test
        func aStoppedEngineCanStartAgainOnAFreshServer() async throws {
            let engine = try engine()
            #expect(!engine.isRunning)
            let first = try await engine.start(port: 0)
            #expect(engine.isRunning && engine.boundPort == first)
            try await engine.stop()
            #expect(!engine.isRunning && engine.boundPort == nil)
            let second = try await engine.start(port: 0)
            #expect(engine.boundPort == second)
            try await engine.stop()
        }

        @Test
        func aBusyPortFallsBackToAFreeOneWhenAllowed() async throws {
            let other = try engine()
            let taken = try await other.start(port: 0)
            let engine = try engine()
            try engine.settings.update { $0.autoSelectPort = true }
            let bound = try await engine.start(port: taken)
            #expect(bound != taken)
            try await engine.stop(); try await other.stop()
        }

        @Test
        func aBusyPortFailsTheStartWhenFallingBackIsOff() async throws {
            let other = try engine()
            let taken = try await other.start(port: 0)
            let engine = try engine()
            try engine.settings.update { $0.autoSelectPort = false }
            await #expect(throws: (any Error).self) { try await engine.start(port: taken) }
            try await other.stop()
        }

        @Test
        func socksAnswersOverIPv6WhenListeningOnAllInterfacesWithIPv6() async throws {
            let engine = try engine()
            let socksPort = try freeLoopbackPort()
            try engine.settings.update {
                $0.listenOnAllInterfaces = true; $0.listenOnIPv6 = true
                $0.socks = SocksSettings(isEnabled: true, port: socksPort)
            }
            _ = try await engine.start(port: 0)
            let channel = try? await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .connect(host: "::1", port: socksPort).get()
            #expect(channel != nil)
            try? await channel?.close()
            try await engine.stop()
        }

        @Test
        func anEditMadeOutsideTheEngineIsPickedUpWhileRunning() async throws {
            let engine = try engine()
            _ = try await engine.start(port: 0)
            let settingsFile = URL(fileURLWithPath: "/fake-home/.watcher/settings.json")
            let outside = SettingsStore(url: settingsFile, files: files.access)
            try outside.update { $0.maxFlows = 7 }
            #expect(await eventually { engine.store.maxFlows == 7 })
            try await engine.stop()
        }

        @Test
        func aPACScriptIsLoadedOncePerLocation() async throws {
            let loads = LockedBox<[String]>([])
            let engine = try engine(pacLoader: { location in
                loads.mutate { $0.append(location) }
                return try PACEvaluator(script: "function FindProxyForURL() { return 'DIRECT'; }")
            })
            _ = try await engine.start(port: 0)
            for location in ["file:///a.pac", "file:///a.pac", "file:///b.pac"] {
                try await engine.updateSettings {
                    $0.externalProxy.isEnabled = true; $0.externalProxy.kind = .pac; $0.externalProxy.pacURL = location
                }
            }
            #expect(loads.value == ["file:///a.pac", "file:///b.pac"])
            try await engine.stop()
        }

        @Test
        func aPACScriptThatCannotBeLoadedIsLogged() async throws {
            let engine = try engine()
            _ = try await engine.start(port: 0)
            try await engine.updateSettings {
                $0.externalProxy.isEnabled = true; $0.externalProxy.kind = .pac
                $0.externalProxy.pacURL = "file:///a.pac"
            }
            #expect(logged.value.contains("PAC: no PAC in this test"))
            try await engine.stop()
        }

        @Test
        func protobufSchemasThatCannotBeReadAreLogged() async throws {
            let engine = try engine()
            _ = try await engine.start(port: 0)
            files.write(Data([0xFF]), to: "/schemas/broken.desc")
            try await engine.updateSettings { $0.protobufSchemas = ["/schemas/missing.desc", "/schemas/broken.desc"] }
            #expect(logged.value.contains { $0.hasPrefix("Protobuf schema /schemas/missing.desc:") })
            #expect(logged.value.contains("Protobuf schemas could not be parsed"))
            try await engine.stop()
        }
    }
}
