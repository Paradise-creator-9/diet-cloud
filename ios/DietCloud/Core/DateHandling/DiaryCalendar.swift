import Foundation

/// Diary day keys aligned with Web `dateKey` in `src/main.tsx`:
/// local calendar year/month/day → `YYYY-MM-DD`.
///
/// Do **not** hard-code Asia/Tokyo as the app default (that is only the
/// `activity-ingest` server fallback when Shortcuts omit `date`). Prefer
/// `Calendar.current` / device timezone so Web and iOS match on the same device.
struct DiaryCalendar: Sendable {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        var cal = calendar
        // Stable day boundaries for diary math.
        cal.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = cal
    }

    /// Explicit Asia/Tokyo calendar for tests / comparison with ingest fallback.
    static func tokyo() -> DiaryCalendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return DiaryCalendar(calendar: calendar)
    }

    /// Matches Web:
    /// `getFullYear()` / `getMonth()+1` / `getDate()` with zero-padding.
    func dateKey(from date: Date = Date()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    func date(fromDateKey key: String) -> Date? {
        let pieces = key.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    /// Start of local calendar day for `dateKey` (00:00:00).
    func startOfDay(dateKey key: String) -> Date? {
        guard let day = date(fromDateKey: key) else { return nil }
        return calendar.startOfDay(for: day)
    }

    /// Exclusive end of local calendar day (next day 00:00:00).
    func endOfDayExclusive(dateKey key: String) -> Date? {
        guard let start = startOfDay(dateKey: key) else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: start)
    }

    /// Inclusive last instant of the day (end exclusive − 1 second), for display bounds.
    func endOfDayInclusive(dateKey key: String) -> Date? {
        guard let endExclusive = endOfDayExclusive(dateKey: key) else { return nil }
        return endExclusive.addingTimeInterval(-1)
    }

    func isToday(_ key: String, now: Date = Date()) -> Bool {
        dateKey(from: now) == key
    }

    /// Web `buildDates`: unique date keys, newest first (`localeCompare` reverse).
    func sortedDateKeysNewestFirst(_ keys: [String]) -> [String] {
        Array(Set(keys)).sorted { $0 > $1 }
    }

    /// Stable sort for food rows on a day: `created_at` ascending (Web fetch order).
    func sortFoodItemsByCreatedAtAscending<T>(_ items: [T], createdAt: (T) -> String) -> [T] {
        items.sorted { createdAt($0) < createdAt($1) }
    }
}
