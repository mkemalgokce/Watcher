import ArgumentParser
import Foundation
import WatcherCore

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run the proxy and print traffic live.")

    @Option(help: "Port to listen on (default: from settings, 9090).") var port: Int?
    @Flag(help: "Tunnel HTTPS untouched instead of decrypting it.") var noDecrypt = false
    @Option(help: "Write the session to this HAR file when you press Ctrl-C.") var har: String?
    @Option(help: "Write the session to this CSV file when you press Ctrl-C.") var csv: String?
    @Flag(help: "Point the macOS system proxy at Watcher while running.") var systemProxy = false

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let engine = try WatcherEngine()
        engine.onLog = { print("[log] \($0)") }
        let bound = try await engine.start(port: port)
        print("Watcher listening on 127.0.0.1:\(bound)")
        if engine.settings.value.listenOnAllInterfaces {
            for address in LocalNetwork.ipv4Addresses() {
                print("  reachable from devices at \(address.ip):\(bound)  (\(address.interface))")
            }
        }

        if noDecrypt {
            var settings = engine.settings.value
            settings.sslProxying.include = []
            await engine.apply(settings)
        }
        if systemProxy {
            try SystemProxy.enable(port: bound)
        }

        // Headless sessions cannot edit a held message, so breakpoints just continue unchanged.
        let breakpointTask = Task {
            for await _ in engine.breakpoints.changes() {
                for hit in engine.breakpoints.pending {
                    print("[breakpoint] \(hit.phase.rawValue) \(hit.request.method) \(hit.request.url) (continued; use the app to edit)")
                    engine.breakpoints.resolve(hit.id, with: .proceed(request: hit.request, response: hit.response))
                }
            }
        }

        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT)
        signal(SIGINT, SIG_IGN)
        interrupt.setEventHandler {
            Task {
                if systemProxy {
                    try? SystemProxy.disable()
                }
                if let har {
                    try? HAR.export(engine.store.all).write(to: URL(fileURLWithPath: (har as NSString).expandingTildeInPath)); print("Saved \(har)")
                }
                if let csv {
                    try? CSVExporter.export(engine.store.all).write(to: URL(fileURLWithPath: (csv as NSString).expandingTildeInPath)); print("Saved \(csv)")
                }
                breakpointTask.cancel()
                try? await engine.stop()
                Foundation.exit(0)
            }
        }
        interrupt.resume()

        var printed = Set<Flow.ID>()
        for await event in engine.store.events() {
            // Flows update several times (streamed headers, WebSocket messages); print each once it has finished.
            guard case let .updated(flow) = event, flow.state != .pending, let response = flow.response, printed.insert(flow.id).inserted else { continue }
            let milliseconds = Int((flow.duration ?? 0) * 1000)
            let tools = flow.appliedTools.isEmpty ? "" : "  [\(flow.appliedTools.joined(separator: ", "))]"
            print("\(flow.sequence)  \(response.status)  \(flow.request.method)  \(flow.request.url)  \(milliseconds)ms\(tools)")
        }
    }
}
