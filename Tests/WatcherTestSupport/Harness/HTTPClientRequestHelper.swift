import Foundation

/// Direct (non-proxied) fetch used where the test talks to a listener itself.
public enum HTTPClientRequestHelper {
    public static func url(_ string: String) -> URL {
        URL(string: string)!
    }

    public static func fetch(_ url: URL) async throws -> String {
        let (data, _) = try await URLSession(configuration: .ephemeral).data(from: url)
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }
}
