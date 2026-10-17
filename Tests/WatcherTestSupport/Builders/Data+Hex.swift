import Foundation

public extension Data {
    /// Bytes written as pairs of hex digits, such as `"ca48"`.
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).map { UInt8(hex.dropFirst($0).prefix(2), radix: 16)! })
    }
}
