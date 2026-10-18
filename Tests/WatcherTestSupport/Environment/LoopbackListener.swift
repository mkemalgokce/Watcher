import Foundation

/// Holds a port on 127.0.0.1 that the system handed out, so nothing else can bind it until this object goes away.
public final class LoopbackListener {
    public let port: Int
    private let descriptor: Int32

    public init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw TestSupportError("socket() failed: \(errno)") }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                let isBound = bind(descriptor, address, length) == 0 && getsockname(descriptor, address, &length) == 0
                return isBound && listen(descriptor, 1) == 0
            }
        }
        guard bound else {
            close(descriptor)
            throw TestSupportError("could not listen on 127.0.0.1:0: \(errno)")
        }
        self.descriptor = descriptor
        port = Int(UInt16(bigEndian: address.sin_port))
    }

    deinit {
        close(descriptor)
    }
}
