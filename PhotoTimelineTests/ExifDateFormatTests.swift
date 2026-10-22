import Foundation
import Testing
@testable import PhotoTimeline

struct ExifDateFormatTests {
    @Test func parsesWithOffset() throws {
        let date = try #require(ExifDateFormat.date(from: "2024:06:15 14:30:00", offset: "+02:00"))
        #expect(date == ISO8601DateFormatter().date(from: "2024-06-15T12:30:00Z"))
    }

    @Test func roundTripsInTimeZone() throws {
        let tz = try #require(ExifDateFormat.timeZone(fromOffset: "-05:30"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let string = ExifDateFormat.string(from: date, in: tz)
        #expect(ExifDateFormat.date(from: string, offset: "-05:30") == date)
    }

    @Test func formatsOffset() throws {
        let tz = try #require(TimeZone(secondsFromGMT: -(5 * 3600 + 30 * 60)))
        #expect(ExifDateFormat.offsetString(for: tz, at: Date()) == "-05:30")
        #expect(ExifDateFormat.offsetString(for: TimeZone(secondsFromGMT: 7200)!, at: Date()) == "+02:00")
    }

    @Test func rejectsMalformedOffset() {
        #expect(ExifDateFormat.timeZone(fromOffset: "02:00") == nil)
        #expect(ExifDateFormat.timeZone(fromOffset: "+2") == nil)
    }
}
