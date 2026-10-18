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

    /// `now`, `locale` and `timeZone` decide how dates are written and whether a token has expired.
    public static func run(
        _ operation: Operation,
        _ input: String,
        now: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure(description: "Enter some text first.") }
        let dates = DateWriter(locale: locale, timeZone: timeZone)
        switch operation {
        case .base64Encode, .urlEncode, .hexEncode: return encode(input, operation)
        case .base64Decode, .urlDecode, .hexDecode: return try decode(text, operation)
        case .jsonPretty, .jsonMinify: return try json(text, minify: operation == .jsonMinify)
        case .timestamp: return try timestamp(text, dates: dates)
        case .jwt: return try jwt(text, now: now, dates: dates)
        }
    }

    private struct DateWriter {
        let locale: Locale
        let timeZone: TimeZone

        func callAsFunction(_ date: Date, _ day: Date.FormatStyle.DateStyle) -> String {
            date.formatted(Date.FormatStyle(date: day, time: .standard, locale: locale, timeZone: timeZone))
        }
    }

    private static let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    private static func encode(_ input: String, _ operation: Operation) -> String {
        switch operation {
        case .base64Encode: Data(input.utf8).base64EncodedString()
        case .hexEncode: Data(input.utf8).hexDigits()
        default: input.addingPercentEncoding(withAllowedCharacters: unreserved) ?? input
        }
    }

    private static func decode(_ text: String, _ operation: Operation) throws -> String {
        switch operation {
        case .base64Decode:
            guard let data = Base64Finder.decode(text) else { throw Failure(description: "This is not valid Base64.") }
            guard let text = String(data: data, encoding: .utf8) else { return BodyFormatter.hexDump(data) }
            return JSONFormatter.looksLikeJSON(text) ? JSONFormatter.pretty(text) : text
        case .urlDecode:
            guard let decoded = text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
                throw Failure(description: "Invalid percent-encoding.")
            }
            return decoded
        default:
            let hex = text.filter { !$0.isWhitespace && $0 != ":" }
            guard hex.count % 2 == 0, !hex.isEmpty, hex.allSatisfy(\.isHexDigit) else {
                throw Failure(description: "Enter an even number of hex digits.")
            }
            let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { offset -> UInt8? in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                return UInt8(hex[start ..< hex.index(start, offsetBy: 2)], radix: 16)
            }
            return String(data: Data(bytes), encoding: .utf8) ?? BodyFormatter.hexDump(Data(bytes))
        }
    }

    private static func json(_ text: String, minify: Bool) throws -> String {
        guard (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) != nil else {
            throw Failure(description: "This is not valid JSON.")
        }
        return minify ? JSONFormatter.minify(text) : JSONFormatter.pretty(text)
    }

    private static func timestamp(_ text: String, dates: DateWriter) throws -> String {
        guard let value = Double(text) else { throw Failure(description: "Enter seconds or milliseconds since 1970.") }
        let seconds = value > 100_000_000_000 ? value / 1000 : value // 13 digits are milliseconds
        let date = Date(timeIntervalSince1970: seconds)
        return "\(ISO8601DateFormatter().string(from: date))\n\(dates(date, .complete))"
    }

    private static func jwt(_ text: String, now: Date, dates: DateWriter) throws -> String {
        guard let token = JWT(text.replacingOccurrences(of: "Bearer ", with: "")) else {
            throw Failure(description: "This is not a JWT (three Base64 parts, a JSON header with alg).")
        }
        let expiry = token.expiresAt.map {
            "\n\n// \(token.isExpired(at: now) ? "expired" : "expires") \(dates($0, .abbreviated))"
        }
        return "// header\n\(token.header)\n\n// payload\n\(token.payload)" + (expiry ?? "")
    }
}
