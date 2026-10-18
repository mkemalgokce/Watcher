import Foundation
import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

/// Clock times as the list, inspector and WebSocket messages print them, in the viewer's language and time zone.
@Suite(.tags(.unit))
struct TimestampTests {
    private static let newYear = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00:00 UTC

    private func timestamp(_ zone: String = "UTC", _ language: String = "en_GB") throws -> Timestamp {
        try Timestamp(locale: Locale(identifier: language), timeZone: #require(TimeZone(identifier: zone)))
    }

    /// The hour is compared as a number: whether a single digit is padded is the system's choice and differs by release.
    private func parts(_ clock: String) -> [Int] {
        clock.split(separator: ":").compactMap { Int($0) }
    }

    @Test
    func midnightReadsAsZeroHoursNotTwentyFour() throws {
        #expect(try parts(timestamp().clock(Self.newYear)) == [0, 0, 0])
        #expect(try parts(timestamp().clockWithoutFraction(Self.newYear)) == [0, 0, 0])
    }

    @Test
    func theSameMomentReadsDifferentlyInEachTimeZone() throws {
        #expect(try parts(timestamp("Asia/Tokyo").clock(Self.newYear)) == [9, 0, 0])
        #expect(try parts(timestamp("America/New_York").clock(Self.newYear)) == [19, 0, 0])
        let kolkata = try parts(timestamp("Asia/Kolkata").clock(Self.newYear))
        #expect(kolkata == [5, 30, 0], "a half-hour offset keeps its minutes")
    }

    @Test
    func theDateFollowsTheTimeZoneAcrossMidnight() throws {
        #expect(try timestamp("UTC").abbreviated(Self.newYear).contains("1 Jan 2026"))
        #expect(try timestamp("America/New_York").abbreviated(Self.newYear).contains("31 Dec 2025"))
    }

    @Test
    func theCompleteFormNamesTheWeekday() throws {
        #expect(try timestamp().complete(Self.newYear).contains("Thursday"))
    }

    @Test
    func fractionsOfASecondAreDroppedNotRounded() throws {
        let almostNoon = Date(timeIntervalSince1970: 1_767_225_600 + 43199.999)
        #expect(try parts(timestamp().clock(almostNoon)) == [11, 59, 59])
        #expect(try parts(timestamp().clockWithoutFraction(almostNoon)) == [11, 59, 59])
    }

    @Test
    func theLanguageDecidesTheClockStyle() throws {
        let afternoon = Self.newYear.addingTimeInterval(15 * 3600)
        #expect(try parts(timestamp("UTC", "en_GB").clock(afternoon)) == [15, 0, 0])
        #expect(try timestamp("UTC", "en_US").clock(afternoon).contains("PM"))
    }

    @Test
    func theEnvironmentBuildsItFromTheViewsLanguageAndZone() throws {
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en_GB")
        environment.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(parts(environment.timestamp.clock(Self.newYear)) == [9, 0, 0])
    }
}
