import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ConverterTests {
    /// Dates are written for the injected moment, language and time zone, not this Mac's.
    struct Environment {
        private let posix = Locale(identifier: "en_US_POSIX")
        /// "eyJhbGciOiJIUzI1NiJ9" is {"alg":"HS256"}; "eyJleHAiOjEwMDB9" is {"exp":1000}.
        private let token = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjEwMDB9.sig"

        private func run(
            _ operation: Converter.Operation,
            _ input: String,
            now: Date = Date(),
            zone: String = "UTC"
        ) throws -> String {
            try Converter.run(operation, input, now: now, locale: posix, timeZone: #require(TimeZone(identifier: zone)))
        }

        @Test(arguments: [("UTC", "January 1, 1970", "12:00:00"), ("Asia/Tokyo", "January 1, 1970", "9:00:00")])
        func aTimestampIsWrittenInTheGivenTimeZone(zone: String, day: String, time: String) throws {
            let lines = try run(.timestamp, "0", zone: zone).split(separator: "\n")
            #expect(lines.first == "1970-01-01T00:00:00Z")
            #expect(lines.last?.contains(day) == true)
            #expect(lines.last?.contains(time) == true)
        }

        @Test(arguments: [(999.0, "// expires"), (1000, "// expires"), (1001, "// expired")])
        func aTokenIsExpiredOnlyAfterItsExpiry(now: TimeInterval, label: String) throws {
            let output = try run(.jwt, token, now: Date(timeIntervalSince1970: now))
            #expect(output.split(separator: "\n").last?.hasPrefix(label + " Jan 1, 1970") == true)
        }
    }
}
