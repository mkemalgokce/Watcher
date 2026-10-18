import Foundation

/// The request that follows a SOCKS5 greeting (RFC 1928, section 4), read from the bytes received so far.
enum SocksRequest: Equatable {
    case needMoreBytes
    /// The reply code to refuse with: 7 for a command other than CONNECT, 8 for an address type we do not know.
    case unsupported(code: UInt8)
    case connect(host: String, port: Int, consumed: Int)

    static func parse(_ bytes: [UInt8]) -> SocksRequest {
        guard bytes.count >= 4 else { return .needMoreBytes }
        guard bytes[0] == 5, bytes[1] == 1 else { return .unsupported(code: 7) }
        let host: String, addressEnd: Int
        switch bytes[3] {
        case 1:
            guard bytes.count >= 10 else { return .needMoreBytes }
            host = bytes[4 ..< 8].map(String.init).joined(separator: "."); addressEnd = 8
        case 3:
            guard bytes.count >= 5, bytes.count >= 7 + Int(bytes[4]) else { return .needMoreBytes }
            addressEnd = 5 + Int(bytes[4])
            host = String(bytes: bytes[5 ..< addressEnd], encoding: .utf8) ?? ""
        case 4:
            guard bytes.count >= 22 else { return .needMoreBytes }
            let groups = stride(from: 4, to: 20, by: 2).map { Int(bytes[$0]) << 8 | Int(bytes[$0 + 1]) }
            host = groups.map { String($0, radix: 16) }.joined(separator: ":")
            addressEnd = 20
        default: return .unsupported(code: 8)
        }
        let port = Int(bytes[addressEnd]) << 8 | Int(bytes[addressEnd + 1])
        return .connect(host: host, port: port, consumed: addressEnd + 2)
    }
}
