import Foundation

/// The file system operations the core logic needs, as closures so tests can swap in `FileAccessFake`.
public struct FileAccess: Sendable {
    public var isExecutable: @Sendable (String) -> Bool
    public var fileExists: @Sendable (String) -> Bool
    public var read: @Sendable (URL) throws -> Data
    public var remove: @Sendable (URL) throws -> Void
    /// A path in the temporary directory that no other call returns, ending in `.<extension>`.
    public var temporaryFile: @Sendable (_ extension: String) -> URL

    public init(
        isExecutable: @escaping @Sendable (String) -> Bool,
        fileExists: @escaping @Sendable (String) -> Bool,
        read: @escaping @Sendable (URL) throws -> Data,
        remove: @escaping @Sendable (URL) throws -> Void,
        temporaryFile: @escaping @Sendable (_ extension: String) -> URL
    ) {
        self.isExecutable = isExecutable; self.fileExists = fileExists; self.read = read
        self.remove = remove; self.temporaryFile = temporaryFile
    }
}
