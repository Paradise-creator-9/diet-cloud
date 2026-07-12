import XCTest
@testable import DietCloud

final class DiaryCalendarTests: XCTestCase {
    func testDateKeyMatchesLocalCalendarComponents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)! // fixed offset

        let diary = DiaryCalendar(calendar: calendar)

        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 12
        components.hour = 23
        components.minute = 30
        let date = calendar.date(from: components)!

        XCTAssertEqual(diary.dateKey(from: date), "2026-07-12")
    }

    func testDateKeyZeroPads() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let diary = DiaryCalendar(calendar: calendar)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        let date = calendar.date(from: components)!

        XCTAssertEqual(diary.dateKey(from: date), "2026-01-05")
    }

    func testRoundTripDateKey() {
        let diary = DiaryCalendar()
        let key = diary.dateKey()
        let restored = diary.date(fromDateKey: key)
        XCTAssertNotNil(restored)
        XCTAssertEqual(diary.dateKey(from: restored!), key)
    }
}
