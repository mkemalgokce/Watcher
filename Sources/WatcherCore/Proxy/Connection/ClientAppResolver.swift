import Foundation
import NIO

/// Looks up the program behind a client connection once and remembers the answer for the connection's later requests.
final class ClientAppResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: String??
    private let lookup: @Sendable (Int) -> String?

    init(lookup: @escaping @Sendable (Int) -> String?) {
        self.lookup = lookup
    }

    func app(for channel: Channel) async -> String? {
        if let known = lock.withLock({ cached }) {
            return known
        }
        // A plain connection knows its peer itself; an HTTP/2 stream channel asks the connection it belongs to.
        let port = channel.remoteAddress?.port ?? channel.parent?.remoteAddress?.port
        let name = await Task.detached { [lookup] in port.flatMap(lookup) }.value
        lock.withLock { cached = .some(name) }
        return name
    }
}
