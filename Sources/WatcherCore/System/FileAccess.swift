import Foundation

/// The file system operations the settings store and the Charles converter need, one closure each.
public struct FileAccess: Sendable {
    public var isExecutable: @Sendable (String) -> Bool
    public var fileExists: @Sendable (String) -> Bool
    public var isDirectory: @Sendable (String) -> Bool
    public var read: @Sendable (URL) throws -> Data
    public var writeAtomically: @Sendable (Data, URL) throws -> Void
    public var remove: @Sendable (URL) throws -> Void
    /// Fails when the destination exists.
    public var move: @Sendable (_ from: URL, _ to: URL) throws -> Void
    /// Creates intermediate folders too; succeeds when the folder exists.
    public var createDirectory: @Sendable (URL) throws -> Void
    /// The files and folders directly inside a folder; throws when it does not exist.
    public var contentsOfDirectory: @Sendable (URL) throws -> [URL]
    public var setPermissions: @Sendable (_ mode: Int, _ path: String) throws -> Void
    public var modificationDate: @Sendable (String) -> Date?
    /// A path in the temporary directory that no other call returns, ending in `.<extension>`.
    public var temporaryFile: @Sendable (_ extension: String) -> URL

    public init(
        isExecutable: @escaping @Sendable (String) -> Bool,
        fileExists: @escaping @Sendable (String) -> Bool,
        isDirectory: @escaping @Sendable (String) -> Bool,
        read: @escaping @Sendable (URL) throws -> Data,
        writeAtomically: @escaping @Sendable (Data, URL) throws -> Void,
        remove: @escaping @Sendable (URL) throws -> Void,
        move: @escaping @Sendable (_ from: URL, _ to: URL) throws -> Void,
        createDirectory: @escaping @Sendable (URL) throws -> Void,
        contentsOfDirectory: @escaping @Sendable (URL) throws -> [URL],
        setPermissions: @escaping @Sendable (_ mode: Int, _ path: String) throws -> Void,
        modificationDate: @escaping @Sendable (String) -> Date?,
        temporaryFile: @escaping @Sendable (_ extension: String) -> URL
    ) {
        self.isExecutable = isExecutable; self.fileExists = fileExists; self.isDirectory = isDirectory
        self.read = read; self.writeAtomically = writeAtomically; self.remove = remove; self.move = move
        self.createDirectory = createDirectory; self.contentsOfDirectory = contentsOfDirectory
        self.setPermissions = setPermissions
        self.modificationDate = modificationDate; self.temporaryFile = temporaryFile
    }
}
