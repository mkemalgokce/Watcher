import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ProtobufSchemaTests {
    @Test
    func schemaNamesFieldsEnumsAndNestedMessages() throws {
        let address = field(1, Array("Address".utf8)) + field(2, fieldDescriptor("city", 1, type: 9))
        let role = field(1, Array("Role".utf8)) + field(2, field(1, Array("ADMIN".utf8)) + number(2, 1))
        let user = field(1, Array("User".utf8))
            + field(2, fieldDescriptor("name", 1, type: 9)) + field(2, fieldDescriptor("id", 2, type: 5))
            + field(2, fieldDescriptor("tags", 3, label: 3, type: 9))
            + field(2, fieldDescriptor("home", 4, type: 11, typeName: ".demo.Address"))
            + field(2, fieldDescriptor("role", 5, type: 14, typeName: ".demo.Role"))
            + field(2, fieldDescriptor("scores", 6, label: 3, type: 5))
        let file = field(2, Array("demo".utf8)) + field(4, user) + field(4, address) + field(5, role)
        let schema = try ProtobufSchema(descriptorSet: Data(field(1, file)))

        let message = field(1, Array("Ada".utf8)) + number(2, 7) + field(3, Array("a".utf8)) + field(3, Array("b".utf8))
            + field(4, field(1, Array("Paris".utf8))) + number(5, 1) + field(6, varint(3) + varint(300))
        #expect(schema.describe(Data(message), as: "demo.User") == """
        name: "Ada"
        id: 7
        tags: "a"
        tags: "b"
        home {
          city: "Paris"
        }
        role: ADMIN
        scores: 3
        scores: 300
        """)
        #expect(schema.describe(Data(message), as: "demo.Missing") == nil)
        #expect(throws: (any Error).self) { try ProtobufSchema(descriptorSet: Data([0xFF])) }
    }

    private func varint(_ value: Int) -> [UInt8] {
        var remaining = value, out: [UInt8] = []
        repeat {
            out.append(UInt8(remaining & 0x7F) | (remaining > 0x7F ? 0x80 : 0)); remaining >>= 7
        } while remaining > 0
        return out
    }

    private func field(_ number: Int, _ bytes: [UInt8]) -> [UInt8] {
        varint(number << 3 | 2) + varint(bytes.count) + bytes
    }

    private func number(_ number: Int, _ value: Int) -> [UInt8] {
        varint(number << 3) + varint(value)
    }

    private func fieldDescriptor(
        _ name: String,
        _ index: Int,
        label: Int = 1,
        type: Int,
        typeName: String = ""
    ) -> [UInt8] {
        field(1, Array(name.utf8)) + number(3, index) + number(4, label) + number(5, type)
            + (typeName.isEmpty ? [] : field(6, Array(typeName.utf8)))
    }
}
