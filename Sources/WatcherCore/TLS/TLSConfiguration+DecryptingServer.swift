import NIOSSL

extension TLSConfiguration {
    /// What Watcher presents to a client whose traffic it decrypts: HTTP/2 only when offered, secrets to `keyLog`.
    static func decryptingServer(
        chain: [NIOSSLCertificateSource],
        key: NIOSSLPrivateKeySource,
        offerHTTP2: Bool,
        keyLog: NIOSSLKeyLogCallback?
    ) -> TLSConfiguration {
        var configuration = makeServerConfiguration(certificateChain: chain, privateKey: key)
        configuration.applicationProtocols = offerHTTP2 ? ["h2", "http/1.1"] : ["http/1.1"]
        configuration.keyLogCallback = keyLog
        return configuration
    }
}
