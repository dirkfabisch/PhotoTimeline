import Foundation

/// EXIF stores local wall-clock time ("yyyy:MM:dd HH:mm:ss") plus an optional
/// offset tag ("+02:00"). This type converts between that pair and `Date`.
nonisolated enum ExifDateFormat {
    static func date(from string: String, offset: String?) -> Date? {
        let tz = offset.flatMap(timeZone(fromOffset:)) ?? .current
        return formatter(in: tz).date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func string(from date: Date, in timeZone: TimeZone) -> String {
        formatter(in: timeZone).string(from: date)
    }

    static func offsetString(for timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        return String(format: "%@%02d:%02d", sign, minutes / 60, minutes % 60)
    }

    /// Parses "+02:00" / "-05:30". Returns nil for malformed values.
    static func timeZone(fromOffset offset: String) -> TimeZone? {
        let parts = offset.trimmingCharacters(in: .whitespaces).dropFirst().split(separator: ":")
        guard let sign = offset.trimmingCharacters(in: .whitespaces).first, sign == "+" || sign == "-",
              parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let seconds = (h * 3600 + m * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }

    /// ISO 8601 with offset, as used by XMP (`xmp:CreateDate`, `photoshop:DateCreated`).
    static func xmpString(from date: Date, in timeZone: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private static func formatter(in timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }
}
