import Foundation

/// A TCP socket bound on 127.0.0.1 and closed when it goes away; port 0 takes whatever the system hands out.
public final class LoopbackSocket {
    public let port: Int
    private let descriptor: Int32

    public init(port: Int = 0) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw TestSupportError("socket() failed: \(errno)") }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, length) == 0 && getsockname(descriptor, $0, &length) == 0
            }
        }
        guard bound else {
            close(descriptor)
            throw TestSupportError("could not bind 127.0.0.1:\(port): \(errno)")
        }
        self.descriptor = descriptor
        self.port = Int(UInt16(bigEndian: address.sin_port))
    }

    deinit {
        close(descriptor)
    }
}
