import Foundation

/// Diary day keys aligned with Web `dateKey` in `src/main.tsx`:
/// local calendar year/month/day → `YYYY-MM-DD`.
///
/// Do **not** hard-code Asia/Tokyo here (that is only the activity-ingest
/// server fallback when Shortcuts omit `date`).
struct DiaryCalendar: Sendable {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
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
}
