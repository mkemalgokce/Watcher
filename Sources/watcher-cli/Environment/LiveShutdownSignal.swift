import Foundation

enum LiveShutdownSignal {
    /// Ctrl-C, `kill` and a closed terminal.
    static let stopRequest: ShutdownSignal = stopRequest(on: [SIGINT, SIGTERM, SIGHUP])

    /// Each of `signals`, caught instead of ending the process so the command can clean up first, such as putting the
    /// system proxy back. They stay ignored afterwards, so a repeat cannot cut that clean-up short.
    static func stopRequest(on signals: [Int32]) -> ShutdownSignal {
        {
            AsyncStream { continuation in
                let sources = signals.map { number in
                    let source = DispatchSource.makeSignalSource(signal: number)
                    signal(number, SIG_IGN)
                    source.setEventHandler { continuation.yield() }
                    source.resume()
                    return source
                }
                continuation.onTermination = { _ in sources.forEach { $0.cancel() } }
            }
        }
    }
}
