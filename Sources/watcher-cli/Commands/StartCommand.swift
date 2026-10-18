import ArgumentParser
import Foundation
import WatcherCore

struct Start: AsyncParsableCommand {
    typealias Output = @Sendable (String) -> Void

    static let configuration = CommandConfiguration(abstract: "Run the proxy and print traffic live.")

    @Option(help: "Port to listen on (default: from settings, 9090).") var port: Int?
    @Flag(help: "Tunnel HTTPS untouched instead of decrypting it.") var noDecrypt = false
    @Option(help: "Write the session to this HAR file when you press Ctrl-C.") var har: String?
    @Option(help: "Write the session to this CSV file when you press Ctrl-C.") var csv: String?
    @Flag(help: "Point the macOS system proxy at Watcher while running.") var systemProxy = false

    func validate() throws {
        try PortOption.validate(port, allowsAny: true)
    }

    func run() async throws {
        try await run(in: .live)
    }

    func run(in environment: CLIEnvironment) async throws {
        let output = environment.output
        let (engine, bound) = try await environment.startEngine(port: port, decryptsHTTPS: !noDecrypt) {
            output("[log] \($0)")
        }
        output("Watcher listening on 127.0.0.1:\(bound)")
        if !systemProxy {
            environment.restoreLeftoverSystemProxy(report: output)
        }
        if engine.settings.value.listenOnAllInterfaces {
            for address in environment.lanAddresses() {
                output("  reachable from devices at \(address.ip):\(bound)  (\(address.interface))")
            }
        }
        let tasks = [
            Self.continueBreakpoints(of: engine, output: output), Self.printFinishedFlows(of: engine, output: output),
        ]
        // Caught before the system proxy is pointed at Watcher, so a stop from then on still puts it back.
        let stopRequests = environment.shutdownSignal()
        if systemProxy {
            do {
                try environment.systemProxy.enable(port: bound)
            } catch {
                await Self.stop(tasks)
                try? await shutDown(engine, in: environment)
                throw error
            }
        }
        for await _ in stopRequests {
            break
        }
        await Self.stop(tasks)
        try await shutDown(engine, in: environment)
    }

    /// Waits for the tasks to end, so no line prints after the `Saved` ones.
    private static func stop(_ tasks: [Task<Void, Never>]) async {
        tasks.forEach { $0.cancel() }
        for task in tasks {
            await task.value
        }
    }

    /// Headless sessions cannot edit a held message, so breakpoints just continue unchanged. Hits held before the
    /// subscription (the proxy was already taking traffic) are continued first, as `changes()` does not replay.
    private static func continueBreakpoints(
        of engine: any EngineControlling,
        output: @escaping Output
    ) -> Task<Void, Never> {
        let changes = engine.breakpoints.changes()
        return Task {
            continuePending(of: engine, output: output)
            for await _ in changes {
                continuePending(of: engine, output: output)
            }
        }
    }

    private static func continuePending(of engine: any EngineControlling, output: Output) {
        for hit in engine.breakpoints.pending {
            let request = hit.request
            let held = "\(hit.phase.rawValue) \(request.method) \(request.url)"
            output("[breakpoint] \(held) (continued; use the app to edit)")
            engine.breakpoints.resolve(hit.id, with: .proceed(request: request, response: hit.response))
        }
    }

    /// Flows that finished before the subscription are printed first, as `events()` does not replay.
    private static func printFinishedFlows(
        of engine: any EngineControlling,
        output: @escaping Output
    ) -> Task<Void, Never> {
        let events = engine.store.events()
        let finishedEarly = engine.store.all
        return Task {
            var lines = FinishedFlowLines()
            for flow in finishedEarly {
                lines.line(for: .updated(flow)).map(output)
            }
            for await event in events {
                lines.line(for: event).map(output)
            }
        }
    }

    private func shutDown(_ engine: any EngineControlling, in environment: CLIEnvironment) async throws {
        if systemProxy {
            try? environment.systemProxy.disable()
        }
        let flows = engine.store.all
        let savedHAR = save(try HAR.export(flows), to: har, in: environment)
        let savedCSV = save(CSVExporter.export(flows), to: csv, in: environment)
        try? await engine.stop()
        guard savedHAR, savedCSV else { throw ExitCode.failure }
    }

    /// False when `path` was given but could not be written.
    private func save(
        _ data: @autoclosure () throws -> Data,
        to path: String?,
        in environment: CLIEnvironment
    ) -> Bool {
        guard let path else { return true }
        do {
            try environment.files.writeAtomically(data(), environment.url(forPath: path))
            environment.output("Saved \(path)")
            return true
        } catch {
            environment.errorOutput("Could not save \(path): \(error.localizedDescription)")
            return false
        }
    }
}
