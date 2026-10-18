import Foundation

/// How an external tool finished: its exit status and everything it printed to standard output.
public struct ToolOutput {
    public let status: Int32
    public let data: Data

    public var text: String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: data, as: UTF8.self)
    }
}
