import Foundation

/// How a moment is written on screen, in the language and time zone the view is shown in.
struct Timestamp {
    var locale: Locale = .current
    var timeZone: TimeZone = .current

    func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: locale, timeZone: timeZone))
    }

    func clockWithoutFraction(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute().second())
    }

    func abbreviated(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone))
    }

    func complete(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .complete, time: .standard, locale: locale, timeZone: timeZone))
    }
}
