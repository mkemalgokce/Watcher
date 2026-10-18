import Foundation

public extension FileAccess {
    static let live = FileAccess(
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        isDirectory: { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        },
        read: { try Data(contentsOf: $0) },
        writeAtomically: { try $0.write(to: $1, options: .atomic) },
        remove: { try FileManager.default.removeItem(at: $0) },
        move: { try FileManager.default.moveItem(at: $0, to: $1) },
        createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
        contentsOfDirectory: { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) },
        writePrivately: { try writePrivately($0, to: $1) },
        appendPrivately: { try appendPrivately($0, to: $1) },
        modificationDate: { (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date },
        temporaryFile: {
            FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString).\($0)")
        }
    )

    /// Writes a 0600 file beside `url` and renames it over `url`, so no reader ever sees wider permissions or half a file.
    private static func writePrivately(_ data: Data, to url: URL) throws {
        let name = ".\(url.lastPathComponent).\(UUID().uuidString)"
        let temporary = url.deletingLastPathComponent().appendingPathComponent(name)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw lastError() }
        do {
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.close()
            guard rename(temporary.path, url.path) == 0 else { throw lastError() }
        } catch {
            unlink(temporary.path)
            throw error
        }
    }

    private static func appendPrivately(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard descriptor >= 0 else { throw lastError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.close()
    }

    private static func lastError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
