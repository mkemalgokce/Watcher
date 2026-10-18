import Foundation
import NIO
import NIOSSL

/// Appends TLS session secrets (NSS key-log format: `CLIENT_RANDOM ...`) to a file so Wireshark can decrypt captures.
final class KeyLogFile: Sendable {
    private let url: URL
    private let files: FileAccess

    /// The file is created readable by its owner only: it holds secrets that decrypt recorded traffic.
    init?(path: String, files: FileAccess) {
        url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        self.files = files
        guard (try? files.appendPrivately(Data(), url)) != nil else { return nil }
    }

    var callback: NIOSSLKeyLogCallback {
        { [url, files] line in
            var line = line
            guard let text = line.readString(length: line.readableBytes) else { return }
            try? files.appendPrivately(Data((text + "\n").utf8), url)
        }
    }
}
