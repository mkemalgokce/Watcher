import Foundation
import WatcherCore

/// An in-memory file system: files are paths with contents, executables a set of paths.
public final class FileAccessFake: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var executables: Set<String>
    private var temporaryCount = 0

    public init(files: [String: Data] = [:], executables: Set<String> = []) {
        self.files = files; self.executables = executables
    }

    public var paths: Set<String> {
        lock.withLock { Set(files.keys) }
    }

    public func write(_ data: Data, to path: String) {
        lock.withLock { files[path] = data }
    }

    public var access: FileAccess {
        FileAccess(
            isExecutable: { [self] path in lock.withLock { executables.contains(path) } },
            fileExists: { [self] path in lock.withLock { files[path] != nil } },
            read: { [self] url in
                guard let data = lock.withLock({ files[url.path] }) else { throw CocoaError(.fileReadNoSuchFile) }
                return data
            },
            remove: { [self] url in
                guard lock.withLock({ files.removeValue(forKey: url.path) }) != nil else {
                    throw CocoaError(.fileNoSuchFile)
                }
            },
            temporaryFile: { [self] pathExtension in
                lock.withLock {
                    temporaryCount += 1
                    return URL(fileURLWithPath: "/fake-tmp/\(temporaryCount).\(pathExtension)")
                }
            }
        )
    }
}
