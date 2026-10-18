/// Splits protobuf wire data into (field number, value) pairs, the step both the schema and the schema-less decoder share.
enum ProtobufWireReader {
    enum Value: Equatable { case varint(UInt64), fixed64(UInt64), fixed32(UInt32), bytes([UInt8]) }

    struct Malformed: Error, CustomStringConvertible { let description: String }

    static func entries(_ bytes: [UInt8]) throws -> [(field: Int, value: Value)] {
        var result: [(field: Int, value: Value)] = []
        var position = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 64, by: 7) {
                guard position < bytes.count else { throw Malformed(description: "truncated varint") }
                let byte = bytes[position]; position += 1
                value |= UInt64(byte & 0x7F) << UInt64(shift)
                if byte & 0x80 == 0 {
                    return value
                }
            }
            throw Malformed(description: "varint too long")
        }
        func littleEndian(_ width: Int, _ name: String) throws -> UInt64 {
            guard position + width <= bytes.count else { throw Malformed(description: "truncated \(name)") }
            defer { position += width }
            return bytes[position ..< position + width].enumerated().reduce(UInt64(0)) {
                $0 | UInt64($1.element) << UInt64($1.offset * 8)
            }
        }
        while position < bytes.count {
            let key = try varint()
            let field = Int(key >> 3)
            guard field > 0 else { throw Malformed(description: "bad field number") }
            switch key & 7 {
            case 0: try result.append((field, .varint(varint())))
            case 1: try result.append((field, .fixed64(littleEndian(8, "fixed64"))))
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - position) else { throw Malformed(description: "truncated bytes") }
                result.append((field, .bytes(Array(bytes[position ..< position + Int(length)]))))
                position += Int(length)
            case 5: try result.append((field, .fixed32(UInt32(littleEndian(4, "fixed32")))))
            default: throw Malformed(description: "unsupported wire type")
            }
        }
        return result
    }
}
