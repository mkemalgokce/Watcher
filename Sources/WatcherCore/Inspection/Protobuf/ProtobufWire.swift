import Foundation

/// Schema-less decoder for protobuf wire format: shows field numbers and guessed types.
public enum ProtobufWire {
    private static let maxDepth = 8

    /// The protobuf message in a body; gRPC frames carry a 5-byte header (flag + length) before it.
    static func message(in data: Data, contentType: String?) -> Data {
        contentType?.lowercased().contains("grpc") == true && data.count > 5 ? Data(data.dropFirst(5)) : data
    }

    /// Returns an indented description, or nil when `data` is not valid protobuf.
    public static func describe(_ data: Data) -> String? {
        var lines: [String] = []
        return parse(Array(data), depth: 0, into: &lines) && !lines.isEmpty ? lines.joined(separator: "\n") : nil
    }

    private static func parse(_ bytes: [UInt8], depth: Int, into lines: inout [String]) -> Bool {
        guard let entries = try? ProtobufWireReader.entries(bytes) else { return false }
        let indent = String(repeating: "  ", count: depth)
        for (field, value) in entries {
            switch value {
            case let .varint(number): lines.append("\(indent)\(field): \(number)")
            case let .fixed64(number): lines.append("\(indent)\(field): \(number) (fixed64)")
            case let .fixed32(number): lines.append("\(indent)\(field): \(number) (fixed32)")
            case let .bytes(payload): describe(payload, field: field, depth: depth, into: &lines)
            }
        }
        return true
    }

    /// Printable text wins over a nested-message reading: short strings often parse as valid messages too.
    private static func describe(_ payload: [UInt8], field: Int, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        var nested: [String] = []
        let text = String(bytes: payload, encoding: .utf8)
        if let text, !text.isEmpty, text.unicodeScalars.allSatisfy(isPrintable) {
            lines.append("\(indent)\(field): \"\(text)\"")
        } else if depth < maxDepth, !payload.isEmpty, parse(payload, depth: depth + 1, into: &nested) {
            lines.append("\(indent)\(field) {"); lines += nested; lines.append("\(indent)}")
        } else {
            let more = payload.count > 64 ? "…" : ""
            lines.append("\(indent)\(field): 0x" + payload.prefix(64).hexDigits() + more)
        }
    }

    private static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x20 && scalar.value != 0x7F || scalar == "\n" || scalar == "\t"
    }
}
