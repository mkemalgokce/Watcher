import Foundation

/// Watcher's own session file: the flows as JSON.
public enum SessionFile {
    public static func encode(_ flows: [Flow]) throws -> Data {
        try JSONEncoder().encode(flows)
    }

    public static func decode(_ data: Data) throws -> [Flow] {
        try JSONDecoder().decode([Flow].self, from: data)
    }
}
