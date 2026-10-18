import Foundation

/// Hand-made protobuf wire bytes, enough to build descriptor sets and messages without a compiler.
public enum ProtobufBytes {
    public static func varint(_ value: Int) -> [UInt8] {
        var remaining = value, out: [UInt8] = []
        repeat {
            out.append(UInt8(remaining & 0x7F) | (remaining > 0x7F ? 0x80 : 0)); remaining >>= 7
        } while remaining > 0
        return out
    }

    /// A length-delimited field.
    public static func field(_ number: Int, _ bytes: [UInt8]) -> [UInt8] {
        varint(number << 3 | 2) + varint(bytes.count) + bytes
    }

    /// A varint field.
    public static func number(_ number: Int, _ value: Int) -> [UInt8] {
        varint(number << 3) + varint(value)
    }

    public static func fieldDescriptor(
        _ name: String,
        _ index: Int,
        label: Int = 1,
        type: Int,
        typeName: String = ""
    ) -> [UInt8] {
        field(1, Array(name.utf8)) + number(3, index) + number(4, label) + number(5, type)
            + (typeName.isEmpty ? [] : field(6, Array(typeName.utf8)))
    }

    /// A descriptor set declaring `demo.User { string name = 1; }`.
    public static var userDescriptorSet: Data {
        let user = field(1, Array("User".utf8)) + field(2, fieldDescriptor("name", 1, type: 9))
        return Data(field(1, field(2, Array("demo".utf8)) + field(4, user)))
    }

    /// A `demo.User` message.
    public static func user(named name: String) -> Data {
        Data(field(1, Array(name.utf8)))
    }
}
