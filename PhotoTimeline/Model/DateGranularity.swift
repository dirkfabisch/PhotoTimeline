import Foundation

/// Which parts of a photo's date a drag on the timeline may change.
nonisolated enum DateGranularity: String, Codable, CaseIterable, Identifiable, Sendable {
    case year, yearMonth, day, all

    static let defaultsKey = "defaultGranularity"

    /// Setting from the Settings window, used for new documents.
    static var standard: DateGranularity {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .all
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .year: "Nur Jahr"
        case .yearMonth: "Monat und Jahr"
        case .day: "Tag, Monat und Jahr"
        case .all: "Alles (minutengenau)"
        }
    }

    /// `original` with the parts this granularity allows taken from `target`; `.day` keeps the time.
    /// The day is clamped to the length of the new month (31 → 30, 29 Feb → 28 Feb).
    func apply(_ target: Date, to original: Date, calendar: Calendar = .current) -> Date {
        if self == .all {
            return Date(timeIntervalSinceReferenceDate: (target.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        }
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: original)
        let new = calendar.dateComponents([.year, .month, .day], from: target)
        parts.year = new.year
        if self != .year { parts.month = new.month }
        if self == .day { parts.day = new.day }

        let day = parts.day ?? 1
        parts.day = 1
        guard let firstOfMonth = calendar.date(from: parts),
              let days = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return original }
        parts.day = min(day, days.upperBound - 1)
        return calendar.date(from: parts) ?? original
    }
}
