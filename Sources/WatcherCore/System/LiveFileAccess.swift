import Foundation

public extension FileAccess {
    static let live = FileAccess(
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        read: { try Data(contentsOf: $0) },
        remove: { try FileManager.default.removeItem(at: $0) },
        temporaryFile: {
            FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString).\($0)")
        }
    )
}
