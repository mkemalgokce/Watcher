import Foundation

/// A named snapshot of the session and the tool settings, so a debugging setup can be put away and brought back.
public struct Workspace: Codable, Sendable {
    public var name: String
    public var savedAt: Date
    public var flows: [Flow]
    public var settings: WatcherSettings
}

public final class WorkspaceStore: Sendable {
    public struct InvalidName: Error, CustomStringConvertible {
        public var description: String {
            "Workspace names may only contain letters, digits, spaces, - and _."
        }
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func list() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "workspace" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    public func save(name: String, flows: [Flow], settings: WatcherSettings) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(Workspace(name: name, savedAt: Date(), flows: flows, settings: settings)).write(to: url(for: name), options: .atomic)
    }

    public func load(name: String) throws -> Workspace {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Workspace.self, from: Data(contentsOf: url(for: name)))
    }

    public func delete(name: String) throws {
        try FileManager.default.removeItem(at: url(for: name))
    }

    /// The name becomes a file name, so anything that could leave the directory is refused.
    private func url(for name: String) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        guard !name.isEmpty, name.count <= 80, name.unicodeScalars.allSatisfy(allowed.contains), name.trimmingCharacters(in: .whitespaces) == name else {
            throw InvalidName()
        }
        return directory.appendingPathComponent(name).appendingPathExtension("workspace")
    }
}
