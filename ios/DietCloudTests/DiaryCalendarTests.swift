import XCTest
@testable import DietCloud

final class DiaryCalendarTests: XCTestCase {
    func testDateKeyMatchesLocalCalendarComponents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

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

    func testTokyoTimezoneDateKey() {
        let diary = DiaryCalendar.tokyo()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        // 2026-07-12 00:30 JST
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 12
        components.hour = 0
        components.minute = 30
        let morning = calendar.date(from: components)!
        XCTAssertEqual(diary.dateKey(from: morning), "2026-07-12")

        // 2026-07-12 23:59 JST still same day
        components.hour = 23
        components.minute = 59
        let late = calendar.date(from: components)!
        XCTAssertEqual(diary.dateKey(from: late), "2026-07-12")
    }

    func testMidnightBoundaryNextDay() {
        let diary = DiaryCalendar.tokyo()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 13
        components.hour = 0
        components.minute = 0
        let midnight = calendar.date(from: components)!
        XCTAssertEqual(diary.dateKey(from: midnight), "2026-07-13")
    }

    func testDayStartAndEnd() {
        let diary = DiaryCalendar.tokyo()
        let start = diary.startOfDay(dateKey: "2026-07-12")
        let endExclusive = diary.endOfDayExclusive(dateKey: "2026-07-12")
        XCTAssertNotNil(start)
        XCTAssertNotNil(endExclusive)
        XCTAssertEqual(diary.dateKey(from: start!), "2026-07-12")
        // End exclusive is next day start
        XCTAssertEqual(diary.dateKey(from: endExclusive!), "2026-07-13")
        let inclusive = diary.endOfDayInclusive(dateKey: "2026-07-12")!
        XCTAssertEqual(diary.dateKey(from: inclusive), "2026-07-12")
    }

    func testSortedDateKeysNewestFirst() {
        let diary = DiaryCalendar()
        let sorted = diary.sortedDateKeysNewestFirst(["2026-07-01", "2026-07-12", "2026-07-05"])
        XCTAssertEqual(sorted, ["2026-07-12", "2026-07-05", "2026-07-01"])
    }

    func testSortFoodItemsByCreatedAtStable() {
        let diary = DiaryCalendar()
        struct Row { let id: String; let created: String }
        let rows = [
            Row(id: "b", created: "2026-07-12T10:00:00Z"),
            Row(id: "a", created: "2026-07-12T08:00:00Z"),
            Row(id: "c", created: "2026-07-12T09:00:00Z"),
        ]
        let sorted = diary.sortFoodItemsByCreatedAtAscending(rows) { $0.created }
        XCTAssertEqual(sorted.map(\.id), ["a", "c", "b"])
    }
}
