import Foundation
import WatcherCore

/// An in-memory file system: files are paths with contents; folders and executables are sets of paths.
/// Every write stamps the file with the next of a sequence of modification dates, so two writes always differ.
public final class FileAccessFake: @unchecked Sendable {
    public struct Failure: Error, Equatable {
        public let operation: String

        public init(operation: String) {
            self.operation = operation
        }
    }

    private let lock = NSLock()
    private var files: [String: Data]
    private var executables: Set<String>
    private var directories: Set<String>
    private var modified: [String: Date] = [:]
    private var permissions: [String: Int] = [:]
    private var writeCount = 0
    private var temporaryCount = 0
    private var failingOperations: Set<String> = []

    public init(files: [String: Data] = [:], executables: Set<String> = [], directories: Set<String> = []) {
        self.files = [:]; self.executables = executables; self.directories = directories
        files.forEach { write($1, to: $0) }
    }

    public var paths: Set<String> {
        lock.withLock { Set(files.keys) }
    }

    public var folders: Set<String> {
        lock.withLock { directories }
    }

    public func contents(of path: String) -> Data? {
        lock.withLock { files[path] }
    }

    public func permissions(of path: String) -> Int? {
        lock.withLock { permissions[path] }
    }

    /// Writes as another process would, outside `access`.
    public func write(_ data: Data, to path: String) {
        lock.withLock { store(data, at: path) }
    }

    public func remove(_ path: String) {
        lock.withLock { _ = files.removeValue(forKey: path) }
    }

    /// Makes `operation` (`"write"`, `"move"`, ...) throw `Failure` until `succeed` is called.
    public func fail(_ operation: String) {
        lock.withLock { _ = failingOperations.insert(operation) }
    }

    public func succeed(_ operation: String) {
        lock.withLock { _ = failingOperations.remove(operation) }
    }

    private func store(_ data: Data, at path: String) {
        writeCount += 1
        files[path] = data
        modified[path] = Date(timeIntervalSinceReferenceDate: Double(writeCount))
    }

    private func perform<T>(_ operation: String, _ body: () throws -> T) throws -> T {
        try lock.withLock {
            guard !failingOperations.contains(operation) else { throw Failure(operation: operation) }
            return try body()
        }
    }

    public var access: FileAccess {
        FileAccess(
            isExecutable: { [self] path in lock.withLock { executables.contains(path) } },
            fileExists: { [self] path in lock.withLock { files[path] != nil || directories.contains(path) } },
            isDirectory: { [self] path in lock.withLock { directories.contains(path) } },
            read: { [self] url in
                try perform("read") {
                    guard let data = files[url.path] else { throw CocoaError(.fileReadNoSuchFile) }
                    return data
                }
            },
            writeAtomically: { [self] data, url in try perform("write") { store(data, at: url.path) } },
            remove: { [self] url in
                try perform("remove") {
                    guard files.removeValue(forKey: url.path) != nil else { throw CocoaError(.fileNoSuchFile) }
                }
            },
            move: { [self] source, destination in
                try perform("move") {
                    guard files[destination.path] == nil, let data = files.removeValue(forKey: source.path) else {
                        throw CocoaError(.fileWriteFileExists)
                    }
                    files[destination.path] = data
                    modified[destination.path] = modified.removeValue(forKey: source.path)
                }
            },
            createDirectory: { [self] url in try perform("createDirectory") { _ = directories.insert(url.path) } },
            setPermissions: { [self] mode, path in try perform("setPermissions") { permissions[path] = mode } },
            modificationDate: { [self] path in lock.withLock { files[path] == nil ? nil : modified[path] } },
            temporaryFile: { [self] pathExtension in
                lock.withLock {
                    temporaryCount += 1
                    return URL(fileURLWithPath: "/fake-tmp/\(temporaryCount).\(pathExtension)")
                }
            }
        )
    }
}
