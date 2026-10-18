/// Thrown by support code instead of asserting, so the calling test decides how to report it.
public struct TestSupportError: Error, CustomStringConvertible, Equatable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
