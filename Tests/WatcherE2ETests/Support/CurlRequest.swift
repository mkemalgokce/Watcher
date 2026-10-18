import WatcherTestSupport

/// `curl` sending one request through an HTTP proxy, ignoring any proxy settings in the environment.
enum CurlRequest {
    static func get(_ url: String, throughProxyPort port: Int) throws -> String {
        let curl = try ExternalTool.curl.run([
            "--silent", "--show-error", "--max-time", "10",
            "--noproxy", "", "--proxy", "http://127.0.0.1:\(port)", url,
        ])
        guard curl.status == 0 else { throw TestSupportError("curl exited with \(curl.status)") }
        return curl.text
    }
}
