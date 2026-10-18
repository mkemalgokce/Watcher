import Foundation

enum LiveShutdownSignal {
    /// Ctrl-C, `kill` and a closed terminal, caught instead of ending the process so the command can clean up first,
    /// such as putting the system proxy back.
    static let stopRequest: ShutdownSignal = {
        AsyncStream { continuation in
            let sources = [SIGINT, SIGTERM, SIGHUP].map { number in
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
