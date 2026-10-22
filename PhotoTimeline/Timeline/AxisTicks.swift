import Foundation

/// Calendar-aligned tick marks for a visible slice of the timeline.
nonisolated enum AxisTicks {
    struct Tick {
        var date: Date
        var label: String
    }

    private struct Unit {
        var component: Calendar.Component
        var step: Int
        /// Component the ticks are aligned to (e.g. 15-minute ticks start at the full hour).
        var alignTo: Calendar.Component
        var template: String
        var seconds: Double
    }

    private static let units: [Unit] = [
        Unit(component: .minute, step: 1, alignTo: .hour, template: "HHmm", seconds: 60),
        Unit(component: .minute, step: 5, alignTo: .hour, template: "HHmm", seconds: 300),
        Unit(component: .minute, step: 15, alignTo: .hour, template: "HHmm", seconds: 900),
        Unit(component: .hour, step: 1, alignTo: .day, template: "dMMMHHmm", seconds: 3600),
        Unit(component: .hour, step: 6, alignTo: .day, template: "dMMMHHmm", seconds: 6 * 3600),
        Unit(component: .day, step: 1, alignTo: .month, template: "dMMM", seconds: 86_400),
        Unit(component: .month, step: 1, alignTo: .year, template: "MMMyyyy", seconds: 30 * 86_400),
        Unit(component: .month, step: 3, alignTo: .year, template: "MMMyyyy", seconds: 91 * 86_400),
        Unit(component: .year, step: 1, alignTo: .era, template: "yyyy", seconds: 365 * 86_400),
        Unit(component: .year, step: 5, alignTo: .era, template: "yyyy", seconds: 5 * 365 * 86_400),
        Unit(component: .year, step: 10, alignTo: .era, template: "yyyy", seconds: 10 * 365 * 86_400),
    ]

    static func ticks(from start: Date, to end: Date, pointsPerSecond: Double, minSpacing: Double = 90) -> [Tick] {
        guard end > start,
              let unit = units.first(where: { $0.seconds * pointsPerSecond >= minSpacing }) ?? units.last
        else { return [] }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(unit.template)

        var date = alignedStart(for: start, unit: unit, calendar: calendar)
        var ticks: [Tick] = []
        while date <= end, ticks.count < 2000 {
            if date >= start { ticks.append(Tick(date: date, label: formatter.string(from: date))) }
            guard let next = calendar.date(byAdding: unit.component, value: unit.step, to: date) else { break }
            date = next
        }
        return ticks
    }

    private static func alignedStart(for date: Date, unit: Unit, calendar: Calendar) -> Date {
        if unit.component == .year {
            let year = calendar.component(.year, from: date)
            return calendar.date(from: DateComponents(year: year - year % unit.step)) ?? date
        }
        // At most ~60 steps until `date` — the caller skips those.
        return calendar.dateInterval(of: unit.alignTo, for: date)?.start ?? date
    }
}
