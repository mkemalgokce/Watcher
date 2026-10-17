import Foundation

/// Suggests local ports for Reverse Proxy: the first free port from 10000 upwards.
public enum PortFinder {
    /// First port from `start` that is not in `taken` and can really be bound on localhost.
    public static func firstAvailable(from start: Int = 10000, avoiding taken: Set<Int> = []) -> Int? {
        (start ... 65535).first { !taken.contains($0) && canBind($0) }
    }

    static func canBind(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }
}
