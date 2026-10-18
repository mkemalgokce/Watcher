import Foundation

enum LiveShutdownSignal {
    /// Ctrl-C, caught instead of killing the process so the command can clean up first.
    static let interrupt: ShutdownSignal = {
        AsyncStream { continuation in
            let source = DispatchSource.makeSignalSource(signal: SIGINT)
            signal(SIGINT, SIG_IGN)
            source.setEventHandler { continuation.yield() }
            source.resume()
            continuation.onTermination = { _ in source.cancel() }
        }
    }
}
