import Foundation
import Testing
@testable import PhotoTimeline

struct DateGranularityTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    @Test func yearKeepsEverythingElse() {
        let result = DateGranularity.year.apply(date(2021, 3, 2, 8), to: date(2019, 6, 15, 14, 30, 12), calendar: calendar)
        #expect(result == date(2021, 6, 15, 14, 30, 12))
    }

    @Test func yearMonthKeepsDayAndTime() {
        let result = DateGranularity.yearMonth.apply(date(2022, 9, 28), to: date(2019, 6, 15, 14, 30), calendar: calendar)
        #expect(result == date(2022, 9, 15, 14, 30))
    }

    @Test func dayKeepsTime() {
        let result = DateGranularity.day.apply(date(2022, 9, 28, 3, 59), to: date(2019, 6, 15, 14, 30, 12), calendar: calendar)
        #expect(result == date(2022, 9, 28, 14, 30, 12))
    }

    @Test func dayIsClampedToShorterMonth() {
        let result = DateGranularity.yearMonth.apply(date(2024, 4, 10), to: date(2024, 1, 31, 10), calendar: calendar)
        #expect(result == date(2024, 4, 30, 10))
    }

    @Test func leapDayMovesToLastFebruaryDay() {
        let result = DateGranularity.year.apply(date(2025, 7, 1), to: date(2024, 2, 29, 9), calendar: calendar)
        #expect(result == date(2025, 2, 28, 9))
    }

    @Test func allRoundsToMinute() {
        let result = DateGranularity.all.apply(date(2023, 5, 4, 12, 7, 40), to: date(2019, 1, 1), calendar: calendar)
        #expect(result == date(2023, 5, 4, 12, 8))
    }
}
