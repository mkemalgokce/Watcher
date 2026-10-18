import Foundation

extension Sequence<UInt8> {
    /// Each byte as two lowercase hex digits, such as `ca48`.
    func hexDigits(separator: String = "") -> String {
        map { String(format: "%02x", $0) }.joined(separator: separator)
    }
}
