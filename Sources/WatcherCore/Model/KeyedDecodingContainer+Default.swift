extension KeyedDecodingContainer {
    /// Missing keys fall back to `value`, so settings files written by older versions keep loading.
    func decode<T: Decodable>(_ key: Key, default value: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? value
    }
}
