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
        remove: { try FileManager.default.removeItem(at: $0) },
        temporaryFile: {
            FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString).\($0)")
        }
    )
}
