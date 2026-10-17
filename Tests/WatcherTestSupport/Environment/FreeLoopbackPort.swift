import Foundation

/// A port on 127.0.0.1 the system just handed out, for listeners that cannot bind to 0 and report back, such as the
/// SOCKS and reverse-proxy ones; parallel tests then do not fight over a fixed number.
public func freeLoopbackPort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw TestSupportError("socket() failed: \(errno)") }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descriptor, $0, length) == 0 && getsockname(descriptor, $0, &length) == 0
        }
    }
    guard bound else { throw TestSupportError("could not bind 127.0.0.1:0: \(errno)") }
    return Int(UInt16(bigEndian: address.sin_port))
}
