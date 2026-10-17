import Foundation

/// Schema-less decoder for protobuf wire format: shows field numbers and guessed types.
public enum ProtobufWire {
    private static let maxDepth = 8

    /// Returns an indented description, or nil when `data` is not valid protobuf.
    public static func describe(_ data: Data) -> String? {
        var lines: [String] = []
        return parse(Array(data), depth: 0, into: &lines) && !lines.isEmpty ? lines.joined(separator: "\n") : nil
    }

    private static func parse(_ bytes: [UInt8], depth: Int, into lines: inout [String]) -> Bool {
        var position = 0
        let indent = String(repeating: "  ", count: depth)

        func varint() -> UInt64? {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 70, by: 7) {
                guard position < bytes.count else { return nil }
                let byte = bytes[position]; position += 1
                guard shift < 64 else { return nil }
                value |= UInt64(byte & 0x7F) << UInt64(shift)
                if byte & 0x80 == 0 {
                    return value
                }
            }
            return nil
        }

        while position < bytes.count {
            guard let key = varint(), key >> 3 > 0 else { return false }
            let field = key >> 3
            switch key & 7 {
            case 0:
                guard let value = varint() else { return false }
                lines.append("\(indent)\(field): \(value)")
            case 1:
                guard position + 8 <= bytes.count else { return false }
                let value = bytes[position ..< position + 8].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64($1.offset * 8) }
                position += 8
                lines.append("\(indent)\(field): \(value) (fixed64)")
            case 5:
                guard position + 4 <= bytes.count else { return false }
                let value = bytes[position ..< position + 4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32($1.offset * 8) }
                position += 4
                lines.append("\(indent)\(field): \(value) (fixed32)")
            case 2:
                guard let length = varint(), length <= UInt64(bytes.count - position) else { return false }
                let payload = Array(bytes[position ..< position + Int(length)])
                position += Int(length)
                // Printable text wins over a nested-message reading: short strings often parse as valid messages too.
                var nested: [String] = []
                if let text = String(bytes: payload, encoding: .utf8), !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F || $0 == "\n" || $0 == "\t" }) {
                    lines.append("\(indent)\(field): \"\(text)\"")
                } else if depth < maxDepth, !payload.isEmpty, parse(payload, depth: depth + 1, into: &nested) {
                    lines.append("\(indent)\(field) {"); lines += nested; lines.append("\(indent)}")
                } else {
                    lines.append("\(indent)\(field): 0x" + payload.prefix(64).map { String(format: "%02x", $0) }.joined() + (payload.count > 64 ? "…" : ""))
                }
            default:
                return false
            }
        }
        return true
    }
}
