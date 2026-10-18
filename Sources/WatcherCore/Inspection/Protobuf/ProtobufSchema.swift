import Foundation

/// Decodes protobuf messages with the field names and types from a `.desc` file (`protoc --descriptor_set_out`).
public struct ProtobufSchema: Sendable {
    public struct LoadError: Error, CustomStringConvertible { public let description: String }

    private struct Field {
        let name: String
        let type: Int // FieldDescriptorProto.Type
        let typeName: String // ".package.Message" for message and enum fields
        let isRepeated: Bool
    }

    private var messages: [String: [Int: Field]] = [:]
    private var enums: [String: [Int: String]] = [:]

    public init(descriptorSet: Data) throws {
        for (field, value) in try Self.entries(Array(descriptorSet)) where field == 1 {
            guard case let .bytes(file) = value else { continue }
            try register(file: file)
        }
        if messages.isEmpty {
            throw LoadError(description: "no message types found in descriptor set")
        }
    }

    /// Readable dump of `data` as message `typeName` (e.g. `demo.User`); nil if the type is unknown or the bytes are not that message.
    public func describe(_ data: Data, as typeName: String) -> String? {
        let key = typeName.hasPrefix(".") ? typeName : "." + typeName
        guard messages[key] != nil else { return nil }
        var lines: [String] = []
        return decode(Array(data), type: key, indent: 0, into: &lines) ? lines.joined(separator: "\n") : nil
    }

    // MARK: Descriptor parsing

    private mutating func register(file: [UInt8]) throws {
        var package = "", messageBodies: [[UInt8]] = [], enumBodies: [[UInt8]] = []
        for (field, value) in try Self.entries(file) {
            guard case let .bytes(bytes) = value else { continue }
            switch field {
            case 2: package = String(decoding: bytes, as: UTF8.self)
            case 4: messageBodies.append(bytes)
            case 5: enumBodies.append(bytes)
            default: break
            }
        }
        let prefix = package.isEmpty ? "" : "." + package
        for body in messageBodies {
            try register(message: body, prefix: prefix)
        }
        for body in enumBodies {
            try register(enumType: body, prefix: prefix)
        }
    }

    private mutating func register(message: [UInt8], prefix: String) throws {
        var name = "", fields: [Int: Field] = [:], nested: [[UInt8]] = [], nestedEnums: [[UInt8]] = []
        for (field, value) in try Self.entries(message) {
            guard case let .bytes(bytes) = value else { continue }
            switch field {
            case 1: name = String(decoding: bytes, as: UTF8.self)
            case 2:
                let parsed = try Self.field(from: bytes)
                fields[parsed.number] = parsed.field
            case 3: nested.append(bytes)
            case 4: nestedEnums.append(bytes)
            default: break
            }
        }
        let full = prefix + "." + name
        messages[full] = fields
        for body in nested {
            try register(message: body, prefix: full)
        }
        for body in nestedEnums {
            try register(enumType: body, prefix: full)
        }
    }

    private mutating func register(enumType: [UInt8], prefix: String) throws {
        var name = "", values: [Int: String] = [:]
        for (field, value) in try Self.entries(enumType) {
            guard case let .bytes(bytes) = value else { continue }
            if field == 1 {
                name = String(decoding: bytes, as: UTF8.self)
            }
            if field == 2 {
                var valueName = "", number = 0
                for (inner, innerValue) in try Self.entries(bytes) {
                    if inner == 1, case let .bytes(b) = innerValue {
                        valueName = String(decoding: b, as: UTF8.self)
                    }
                    if inner == 2, case let .varint(n) = innerValue {
                        number = Int(truncatingIfNeeded: n)
                    }
                }
                values[number] = valueName
            }
        }
        enums[prefix + "." + name] = values
    }

    private static func field(from bytes: [UInt8]) throws -> (number: Int, field: Field) {
        var name = "", number = 0, label = 1, type = 0, typeName = ""
        for (field, value) in try entries(bytes) {
            switch (field, value) {
            case let (1, .bytes(b)): name = String(decoding: b, as: UTF8.self)
            case let (3, .varint(n)): number = Int(n)
            case let (4, .varint(n)): label = Int(n)
            case let (5, .varint(n)): type = Int(n)
            case let (6, .bytes(b)): typeName = String(decoding: b, as: UTF8.self)
            default: break
            }
        }
        return (number, Field(name: name, type: type, typeName: typeName, isRepeated: label == 3))
    }

    // MARK: Wire decoding

    private enum Value { case varint(UInt64), fixed64(UInt64), fixed32(UInt32), bytes([UInt8]) }

    /// Splits a message into (field number, value) pairs; throws on truncated or malformed wire data.
    private static func entries(_ bytes: [UInt8]) throws -> [(Int, Value)] {
        var result: [(Int, Value)] = []
        var position = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 64, by: 7) {
                guard position < bytes.count else { throw LoadError(description: "truncated varint") }
                let byte = bytes[position]; position += 1
                value |= UInt64(byte & 0x7F) << UInt64(shift)
                if byte & 0x80 == 0 {
                    return value
                }
            }
            throw LoadError(description: "varint too long")
        }
        while position < bytes.count {
            let key = try varint()
            let field = Int(key >> 3)
            guard field > 0 else { throw LoadError(description: "bad field number") }
            switch key & 7 {
            case 0: try result.append((field, .varint(varint())))
            case 1:
                guard position + 8 <= bytes.count else { throw LoadError(description: "truncated fixed64") }
                result.append((field, .fixed64(bytes[position ..< position + 8].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64($1.offset * 8) })))
                position += 8
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - position) else { throw LoadError(description: "truncated bytes") }
                result.append((field, .bytes(Array(bytes[position ..< position + Int(length)]))))
                position += Int(length)
            case 5:
                guard position + 4 <= bytes.count else { throw LoadError(description: "truncated fixed32") }
                result.append((field, .fixed32(bytes[position ..< position + 4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32($1.offset * 8) })))
                position += 4
            default: throw LoadError(description: "unsupported wire type")
            }
        }
        return result
    }

    private func decode(_ bytes: [UInt8], type: String, indent: Int, into lines: inout [String]) -> Bool {
        guard let fields = messages[type], let entries = try? Self.entries(bytes) else { return false }
        let pad = String(repeating: "  ", count: indent)
        for (number, value) in entries {
            guard let field = fields[number] else { lines.append("\(pad)\(number): \(raw(value))"); continue }
            switch value {
            case let .bytes(payload) where field.type == 11:
                var nested: [String] = []
                guard decode(payload, type: field.typeName, indent: indent + 1, into: &nested) else { return false }
                lines.append("\(pad)\(field.name) {"); lines += nested; lines.append("\(pad)}")
            case let .bytes(payload) where field.type == 9:
                lines.append("\(pad)\(field.name): \"\(String(decoding: payload, as: UTF8.self))\"")
            case let .bytes(payload) where field.type == 12:
                lines.append("\(pad)\(field.name): 0x" + payload.prefix(64).hexDigits())
            case let .bytes(payload):
                // Packed repeated scalars.
                guard let packed = try? Self.packed(payload, type: field.type) else { return false }
                for element in packed {
                    lines.append("\(pad)\(field.name): \(scalar(element, field))")
                }
            default:
                lines.append("\(pad)\(field.name): \(scalar(value, field))")
            }
        }
        return true
    }

    private static func packed(_ bytes: [UInt8], type: Int) throws -> [Value] {
        // Re-use the wire reader by wrapping each element behind a synthetic tag of the right wire type.
        switch type {
        case 1, 6, 16: try stride(from: 0, to: bytes.count - 7, by: 8).flatMap { try entries([0x09] + bytes[$0 ..< $0 + 8]) }.map(\.1)
        case 2, 7, 15: try stride(from: 0, to: bytes.count - 3, by: 4).flatMap { try entries([0x0D] + bytes[$0 ..< $0 + 4]) }.map(\.1)
        default: try entries(wrapVarints(bytes)).map(\.1)
        }
    }

    private static func wrapVarints(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = [], start = true
        for byte in bytes {
            if start {
                result.append(0x08)
            }; result.append(byte); start = byte & 0x80 == 0
        }
        return result
    }

    private func scalar(_ value: Value, _ field: Field) -> String {
        switch (value, field.type) {
        case let (.varint(n), 5), let (.varint(n), 3): "\(Int64(bitPattern: n))"
        case let (.varint(n), 17): "\(Int32(truncatingIfNeeded: Int64(bitPattern: n >> 1) ^ -Int64(bitPattern: n & 1)))"
        case let (.varint(n), 18): "\(Int64(bitPattern: n >> 1) ^ -Int64(bitPattern: n & 1))"
        case let (.varint(n), 8): n == 0 ? "false" : "true"
        case let (.varint(n), 14): enums[field.typeName]?[Int(truncatingIfNeeded: n)] ?? "\(n)"
        case let (.fixed64(n), 1): "\(Double(bitPattern: n))"
        case let (.fixed32(n), 2): "\(Float(bitPattern: n))"
        case let (.fixed64(n), 16): "\(Int64(bitPattern: n))"
        case let (.fixed32(n), 15): "\(Int32(bitPattern: n))"
        default: raw(value)
        }
    }

    private func raw(_ value: Value) -> String {
        switch value {
        case let .varint(n): "\(n)"
        case let .fixed64(n): "\(n)"
        case let .fixed32(n): "\(n)"
        case let .bytes(bytes): "0x" + bytes.prefix(64).hexDigits()
        }
    }
}
