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
        setPermissions: { try FileManager.default.setAttributes([.posixPermissions: $0], ofItemAtPath: $1) },
        modificationDate: { (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date },
        temporaryFile: {
            FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString).\($0)")
        }
    )
}
