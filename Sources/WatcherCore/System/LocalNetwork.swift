import Foundation

/// The Mac's LAN addresses, so a phone or simulator can be pointed at the proxy.
public enum LocalNetwork {
    public struct Address: Equatable, Sendable {
        public let interface: String
        public let ip: String
    }

    /// The IPs of `ipv4Addresses()`, for matching a request's host against.
    public static func addressSet() -> Set<String> {
        Set(ipv4Addresses().map(\.ip))
    }

    /// IPv4 addresses of active, non-loopback interfaces (link-local 169.254.x.x is skipped).
    public static func ipv4Addresses() -> [Address] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [Address] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  Int32(entry.ifa_flags) & (IFF_UP | IFF_LOOPBACK) == IFF_UP else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if !ip.hasPrefix("169.254.") {
                result.append(Address(interface: String(cString: entry.ifa_name), ip: ip))
            }
        }
        return result
    }
}
