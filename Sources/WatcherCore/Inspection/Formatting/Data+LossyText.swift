import Foundation

public extension Data {
    /// The bytes as text for showing: any that are not valid UTF-8 become a replacement character rather than hiding
    /// the whole value. Not for data that has to read back the same.
    var lossyUTF8: String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: self, as: UTF8.self)
    }
}
