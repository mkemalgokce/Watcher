import Foundation

/// Small encode/decode helpers a developer reaches for while reading traffic.
public enum Converter {
    public enum Operation: String, CaseIterable, Identifiable, Sendable {
        case base64Decode = "Base64 decode", base64Encode = "Base64 encode", urlDecode = "URL decode", urlEncode = "URL encode"
        case hexDecode = "Hex to text", hexEncode = "Text to hex", timestamp = "Unix time to date", jsonPretty = "Format JSON", jsonMinify = "Minify JSON", jwt = "Decode JWT"
        public var id: Self {
            self
        }
    }

    public struct Failure: Error, CustomStringConvertible { public let description: String }

    public static func run(_ operation: Operation, _ input: String) throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure(description: "Enter some text first.") }
        switch operation {
        case .base64Decode:
            guard let data = Base64Finder.decode(text) else { throw Failure(description: "This is not valid Base64.") }
            return String(data: data, encoding: .utf8).map { JSONFormatter.looksLikeJSON($0) ? JSONFormatter.pretty($0) : $0 } ?? BodyFormatter.hexDump(data)
        case .base64Encode: return Data(input.utf8).base64EncodedString()
        case .urlDecode:
            guard let decoded = text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else { throw Failure(description: "Invalid percent-encoding.") }
            return decoded
        case .urlEncode: return input.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? input
        case .hexDecode:
            let hex = text.filter { !$0.isWhitespace && $0 != ":" }
            guard hex.count % 2 == 0, !hex.isEmpty, hex.allSatisfy(\.isHexDigit) else { throw Failure(description: "Enter an even number of hex digits.") }
            let bytes = stride(from: 0, to: hex.count, by: 2).map { i -> UInt8 in
                let start = hex.index(hex.startIndex, offsetBy: i); return UInt8(hex[start ..< hex.index(start, offsetBy: 2)], radix: 16)!
            }
            return String(data: Data(bytes), encoding: .utf8) ?? BodyFormatter.hexDump(Data(bytes))
        case .hexEncode: return Data(input.utf8).hexDigits()
        case .timestamp:
            guard let value = Double(text) else { throw Failure(description: "Enter seconds or milliseconds since 1970.") }
            let seconds = value > 100_000_000_000 ? value / 1000 : value // 13 digits are milliseconds
            let date = Date(timeIntervalSince1970: seconds)
            return "\(ISO8601DateFormatter().string(from: date))\n\(date.formatted(date: .complete, time: .standard))"
        case .jsonPretty:
            guard (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) != nil else { throw Failure(description: "This is not valid JSON.") }
            return JSONFormatter.pretty(text)
        case .jsonMinify:
            guard (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) != nil else { throw Failure(description: "This is not valid JSON.") }
            return JSONFormatter.minify(text)
        case .jwt:
            guard let token = JWT(text.replacingOccurrences(of: "Bearer ", with: "")) else { throw Failure(description: "This is not a JWT (three Base64 parts, a JSON header with alg).") }
            return "// header\n\(token.header)\n\n// payload\n\(token.payload)" + (token.expiresAt.map { "\n\n// \($0 < Date() ? "expired" : "expires") \($0.formatted(date: .abbreviated, time: .standard))" } ?? "")
        }
    }
}
