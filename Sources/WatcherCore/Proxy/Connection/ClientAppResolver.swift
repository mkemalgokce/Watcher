import Foundation
import NIO

/// Works out who is behind a client connection once and remembers the answer for the connection's later requests.
final class ClientAppResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: ClientIdentity??
    private let localAddresses: @Sendable () -> Set<String>
    private let lookup: @Sendable (Int) -> ClientIdentity?

    /// `lookup` finds the program behind a local client port; clients from other addresses are devices.
    init(localAddresses: @escaping @Sendable () -> Set<String>, lookup: @escaping @Sendable (Int) -> ClientIdentity?) {
        self.localAddresses = localAddresses
        self.lookup = lookup
    }

    func identity(for channel: Channel) async -> ClientIdentity? {
        if let known = lock.withLock({ cached }) {
            return known
        }
        // A plain connection knows its peer itself; an HTTP/2 stream channel asks the connection it belongs to.
        let peer = channel.remoteAddress ?? channel.parent?.remoteAddress
        let identity = await resolve(peer)
        lock.withLock { cached = .some(identity) }
        return identity
    }

    private func resolve(_ peer: SocketAddress?) async -> ClientIdentity? {
        guard let peer, let address = peer.ipAddress else { return nil }
        guard address == "127.0.0.1" || address == "::1" || localAddresses().contains(address) else {
            return .device(address: address)
        }
        let port = peer.port
        return await Task.detached { [lookup] in port.flatMap(lookup) }.value
    }
}
