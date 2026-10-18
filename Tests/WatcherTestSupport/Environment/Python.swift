import Foundation

/// Runs a short Python script (the system `python3` has `ssl`) and returns what it printed.
/// Throws `TestSupportError` when python3 cannot be started; check `ExternalTool.python3.isAvailable` to skip instead.
public func runPython(_ script: String) throws -> String {
    try ExternalTool.python3.run(["-c", script]).text
}

/// How a script asks the proxy for a tunnel to `host:443`.
public enum ProxyHandshake {
    case httpConnect
    case socks5

    fileprivate func python(host: String) -> String {
        switch self {
        case .httpConnect:
            """
            s.sendall(b"CONNECT \(host):443 HTTP/1.1\\r\\nHost: \(host):443\\r\\n\\r\\n"); s.recv(4096)
            """
        case .socks5:
            """
            s.sendall(bytes([5, 1, 0])); s.recv(2)
            s.sendall(bytes([5, 1, 0, 3, \(host.utf8.count)]) + b"\(host)" + bytes([1, 187])); s.recv(10)
            """
        }
    }
}

/// Python source for "open a tunnel to host:443 through the proxy, then a TLS handshake"; the caller appends statements
/// that use `t` or `err`.
public func pythonTLSViaProxy(
    port: Int,
    host: String,
    verify: Bool,
    alpn: [String] = [],
    handshake: ProxyHandshake = .httpConnect
) -> String {
    """
    import socket, ssl
    s = socket.create_connection(("127.0.0.1", \(port)), timeout=10)
    \(handshake.python(host: host))
    ctx = ssl.create_default_context()
    \(verify ? "" : "ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE")
    \(alpn.isEmpty ? "" : "ctx.set_alpn_protocols([\(alpn.map { "\"\($0)\"" }.joined(separator: ", "))])")
    t = None; err = None
    try: t = ctx.wrap_socket(s, server_hostname="\(host)")
    except Exception as e: err = e
    """
}
