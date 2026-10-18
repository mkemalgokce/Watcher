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
            files: FileAccessFake? = nil,
            pacLoader: @escaping @Sendable (String) async throws -> PACEvaluator = { _ in
                throw PACEvaluator.LoadError(description: "no PAC in this test")
            },
            pacTimeout: Duration = .seconds(10),
            makeServer: @escaping @Sendable (FlowStore, CertificateAuthority) -> ProxyServer = {
                ProxyServer(store: $0, authority: $1, clientApp: { _ in nil })
            }
        ) throws -> WatcherEngine {
            let engine = try WatcherEngine(
                directory: URL(fileURLWithPath: "/fake-home/.watcher"),
                files: (files ?? self.files).access,
                pacLoader: pacLoader,
                pacTimeout: pacTimeout,
                sleep: { _ in try await Task.sleep(for: .milliseconds(5)) },
                makeServer: makeServer
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
            let other = try engine(files: FileAccessFake())
            let taken = try await other.start(port: 0)
            let engine = try engine()
            try engine.settings.update { $0.autoSelectPort = true }
            let bound = try await engine.start(port: taken)
            #expect(bound != taken)
            try await engine.stop(); try await other.stop()
        }

        @Test
        func aBusyPortFailsTheStartWhenFallingBackIsOff() async throws {
            let other = try engine(files: FileAccessFake())
            let taken = try await other.start(port: 0)
            let engine = try engine()
            try engine.settings.update { $0.autoSelectPort = false }
            await #expect(throws: (any Error).self) { try await engine.start(port: taken) }
            try await other.stop()
        }

        private func accepts(port: Int) async -> Bool {
            let channel = try? await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .connect(host: "127.0.0.1", port: port).get()
            try? await channel?.close()
            return channel != nil
        }

        @Test
        func startingARunningEngineStopsTheServerItReplaces() async throws {
            let engine = try engine()
            let first = try await engine.start(port: 0)
            let second = try await engine.start(port: 0)
            try #require(first != second)
            #expect(await !accepts(port: first))
            #expect(await accepts(port: second))
            try await engine.stop()
        }

        @Test
        func anApplyWaitsForTheStartInProgress() async throws {
            let building = LockedBox(false), mayBuild = DispatchSemaphore(value: 0)
            let engine = try engine(makeServer: {
                building.mutate { $0 = true }
                mayBuild.wait()
                return ProxyServer(store: $0, authority: $1, clientApp: { _ in nil })
            })
            let starting = Task { try await engine.start(port: 0) }
            #expect(await eventually { building.value })
            var settings = engine.settings.value
            settings.socks = SocksSettings(isEnabled: true, port: 0)
            let applied = LockedBox(false)
            let applying = Task { await engine.apply(settings); applied.mutate { $0 = true } }
            #expect(await !eventually(timeout: 0.5) { applied.value }, "the apply ran before the start finished")
            mayBuild.signal()
            _ = try await starting.value
            await applying.value
            let socksPort = try #require(engine.socksPort)
            #expect(await accepts(port: socksPort))
            try await engine.stop()
        }

        @Test
        func aPACScriptThatNeverArrivesDoesNotHoldUpTheStart() async throws {
            let engine = try engine(
                pacLoader: { _ in
                    try await sleepUntilCancelled(.zero)
                    throw PACEvaluator.LoadError(description: "cancelled")
                },
                pacTimeout: .milliseconds(50)
            )
            try engine.settings.update {
                $0.externalProxy.isEnabled = true; $0.externalProxy.kind = .pac
                $0.externalProxy.pacURL = "http://pac.test/proxy.pac"
            }
            _ = try await engine.start(port: 0)
            #expect(engine.isRunning)
            #expect(logged.value.contains { $0.hasPrefix("PAC:") && $0.contains("did not answer") }, "\(logged.value)")
            try await engine.stop()
        }

        @Test
        func stoppingDoesNotWaitForAPACScriptStillLoading() async throws {
            let (released, release) = AsyncStream.makeStream(of: Void.self)
            let asked = LockedBox(false)
            let engine = try engine(pacLoader: { _ in
                asked.mutate { $0 = true }
                for await _ in released {}
                throw PACEvaluator.LoadError(description: "released")
            })
            try await engine.start(port: 0)
            var settings = engine.settings.value
            settings.externalProxy.isEnabled = true; settings.externalProxy.kind = .pac
            settings.externalProxy.pacURL = "http://pac.test/proxy.pac"
            let applying = Task { await engine.apply(settings) }
            #expect(await eventually { asked.value })
            try await engine.stop()
            #expect(!engine.isRunning)
            release.finish()
            await applying.value
        }

        @Test
        func socksAnswersOverIPv6WhenListeningOnAllInterfacesWithIPv6() async throws {
            let engine = try engine()
            try engine.settings.update {
                $0.listenOnAllInterfaces = true; $0.listenOnIPv6 = true
                $0.socks = SocksSettings(isEnabled: true, port: 0)
            }
            _ = try await engine.start(port: 0)
            let socksPort = try #require(engine.socksPort)
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
            let settingsFile = WatcherPaths.settingsFile(in: URL(fileURLWithPath: "/fake-home/.watcher"))
            let outside = SettingsStore(url: settingsFile, files: files.access)
            try outside.update { $0.maxFlows = 7 }
            #expect(await eventually { engine.store.maxFlows == 7 })
            try await engine.stop()
        }

        @Test
        func notDecryptingHTTPSHoldsFromTheStartThroughEveryLaterApply() async throws {
            let server = LockedBox<ProxyServer?>(nil)
            let engine = try engine(makeServer: { store, authority in
                let made = ProxyServer(store: store, authority: authority, clientApp: { _ in nil })
                server.mutate { $0 = made }
                return made
            })
            try engine.settings.update { $0.sslProxying.include = ["*"] }
            engine.decryptsHTTPS = false
            _ = try await engine.start(port: 0)
            let proxy = try #require(server.value)
            #expect(!proxy.sslProxying.allows("api.example.com"), "decrypted right after the start")

            let settingsFile = WatcherPaths.settingsFile(in: URL(fileURLWithPath: "/fake-home/.watcher"))
            let outside = SettingsStore(url: settingsFile, files: files.access)
            try outside.update { $0.maxFlows = 7 }
            #expect(await eventually { engine.store.maxFlows == 7 })
            #expect(!proxy.sslProxying.allows("api.example.com"), "decrypted after the settings file changed")

            try await engine.updateSettings { $0.sslProxying.exclude.append("pinned.test") }
            #expect(!proxy.sslProxying.allows("api.example.com"), "decrypted after a settings update")
            #expect(engine.settings.value.sslProxying.include == ["*"])
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
