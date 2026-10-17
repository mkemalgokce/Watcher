import Foundation
import NIO
import NIOSSL

/// Appends TLS session secrets (NSS key-log format: `CLIENT_RANDOM ...`) to a file so Wireshark can decrypt captures.
final class KeyLogFile: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle

    /// The file is created readable by its owner only: it holds secrets that decrypt recorded traffic.
    init?(path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return nil }
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? handle.seekToEnd()
        self.handle = handle
    }

    deinit { try? handle.close() }

    var callback: NIOSSLKeyLogCallback {
        { [self] line in
            var line = line
            guard let text = line.readString(length: line.readableBytes) else { return }
            lock.withLock { try? handle.write(contentsOf: Data((text + "\n").utf8)) }
        }
    }
}
