import Foundation

/// The page a phone or tablet opens (`http://watcher.cert` through the proxy, or the proxy's own address) to install the root certificate.
public struct CertificatePage: Sendable {
    public static let magicHost = "watcher.cert"

    private let der: Data
    private let pem: String

    public init(authority: CertificateAuthority) {
        der = authority.certificateDER; pem = authority.certificatePEM
    }

    /// True for requests meant for Watcher itself rather than for the internet.
    public static func isAddressed(host: String, port: Int, proxyPort: Int?, localAddresses: Set<String> = Set(LocalNetwork.ipv4Addresses().map(\.ip))) -> Bool {
        if host.lowercased() == magicHost {
            return true
        }
        guard let proxyPort, port == proxyPort else { return false }
        return host == "127.0.0.1" || host.lowercased() == "localhost" || localAddresses.contains(host)
    }

    public func response(forPath path: String) -> ResponseRecord {
        switch path.split(separator: "?").first.map(String.init) ?? "/" {
        case "/ca.pem": file(Data(pem.utf8), "application/x-pem-file", "watcher-ca.pem")
        case "/ca.cer": file(der, "application/x-x509-ca-cert", "watcher-ca.cer")
        case "/ca.mobileconfig": file(mobileConfig(), "application/x-apple-aspen-config", "watcher-ca.mobileconfig")
        case "/", "/index.html": ResponseRecord(status: 200, headers: [Header("Content-Type", "text/html; charset=utf-8"), Header("Cache-Control", "no-store")], body: Data(Self.html.utf8))
        default: ResponseRecord(status: 404, headers: [Header("Content-Type", "text/plain")], body: Data("Not found".utf8))
        }
    }

    /// An iOS configuration profile that carries the root certificate; after installing it the user still has to enable full trust in Settings.
    public func mobileConfig() -> Data {
        let payload: [String: Any] = [
            "PayloadType": "com.apple.security.root", "PayloadVersion": 1, "PayloadIdentifier": "com.watcher.ca.cert",
            "PayloadUUID": "6F1D6A52-4B0C-4C2B-9B7E-2A1E5C0D7A11", "PayloadDisplayName": "Watcher Root CA", "PayloadContent": der,
        ]
        let profile: [String: Any] = [
            "PayloadType": "Configuration", "PayloadVersion": 1, "PayloadIdentifier": "com.watcher.ca",
            "PayloadUUID": "0B8F3A0E-5E57-4D6B-8A2D-7C5B1E9A2F22", "PayloadDisplayName": "Watcher Root CA",
            "PayloadDescription": "Lets Watcher show HTTPS traffic from this device.", "PayloadContent": [payload],
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)) ?? Data()
    }

    private func file(_ data: Data, _ type: String, _ name: String) -> ResponseRecord {
        ResponseRecord(status: 200, headers: [Header("Content-Type", type), Header("Content-Disposition", "attachment; filename=\"\(name)\""), Header("Cache-Control", "no-store")], body: data)
    }

    private static let html = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Watcher certificate</title>
    <style>body{font:16px -apple-system,system-ui,sans-serif;margin:24px;max-width:520px;color:#1d1d1f}h1{font-size:22px}a.b{display:block;margin:10px 0;padding:14px;border-radius:12px;background:#0a84ff;color:#fff;text-decoration:none;text-align:center}
    a.b.s{background:#e8e8ed;color:#1d1d1f}ol{padding-left:20px;line-height:1.5}</style></head><body>
    <h1>Install the Watcher certificate</h1>
    <a class="b" href="/ca.mobileconfig">iPhone / iPad profile (.mobileconfig)</a>
    <a class="b s" href="/ca.cer">Certificate (.cer) — Android, macOS</a>
    <a class="b s" href="/ca.pem">Certificate (.pem) — Linux, tools</a>
    <h2>iPhone &amp; iPad</h2><ol><li>Tap the profile button and allow the download.</li><li>Settings → Profile Downloaded → Install.</li>
    <li>Settings → General → About → Certificate Trust Settings → enable <b>Watcher Root CA</b>.</li></ol>
    <h2>Android</h2><ol><li>Download the .cer file.</li><li>Settings → Security → Encryption &amp; credentials → Install a certificate → CA certificate.</li></ol>
    <p>Android apps only trust user certificates if they opt in; browsers and debug builds do.</p></body></html>
    """
}
