import XCTest
import EventKit
@testable import ics_calendar_sync

final class RecurrenceMapperTests: XCTestCase {

    // MARK: - Basic Frequency Tests

    func testParseDailyRule() {
        let rrule = "FREQ=DAILY"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .daily)
        XCTAssertEqual(rule?.interval, 1)
    }

    func testParseWeeklyRule() {
        let rrule = "FREQ=WEEKLY"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .weekly)
    }

    func testParseMonthlyRule() {
        let rrule = "FREQ=MONTHLY"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .monthly)
    }

    func testParseYearlyRule() {
        let rrule = "FREQ=YEARLY"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .yearly)
    }

    // MARK: - Interval Tests

    func testParseWithInterval() {
        let rrule = "FREQ=DAILY;INTERVAL=3"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.interval, 3)
    }

    func testParseEveryTwoWeeks() {
        let rrule = "FREQ=WEEKLY;INTERVAL=2"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .weekly)
        XCTAssertEqual(rule?.interval, 2)
    }

    // MARK: - Count Tests

    func testParseWithCount() {
        let rrule = "FREQ=DAILY;COUNT=10"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.recurrenceEnd)
        XCTAssertEqual(rule?.recurrenceEnd?.occurrenceCount, 10)
    }

    // MARK: - Until Tests

    func testParseWithUntil() {
        let rrule = "FREQ=WEEKLY;UNTIL=20241231T235959Z"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.recurrenceEnd)
        XCTAssertNotNil(rule?.recurrenceEnd?.endDate)
    }

    func testParseWithUntilDateOnly() {
        let rrule = "FREQ=DAILY;UNTIL=20241231"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.recurrenceEnd?.endDate)
    }

    // MARK: - BYDAY Tests

    func testParseByDaySingle() {
        let rrule = "FREQ=WEEKLY;BYDAY=MO"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.daysOfTheWeek)
        XCTAssertEqual(rule?.daysOfTheWeek?.count, 1)
        XCTAssertEqual(rule?.daysOfTheWeek?.first?.dayOfTheWeek, .monday)
    }

    func testParseByDayMultiple() {
        let rrule = "FREQ=WEEKLY;BYDAY=MO,WE,FR"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.daysOfTheWeek)
        XCTAssertEqual(rule?.daysOfTheWeek?.count, 3)

        let days = rule?.daysOfTheWeek?.map { $0.dayOfTheWeek } ?? []
        XCTAssertTrue(days.contains(.monday))
        XCTAssertTrue(days.contains(.wednesday))
        XCTAssertTrue(days.contains(.friday))
    }

    func testParseByDayWithWeekNumber() {
        let rrule = "FREQ=MONTHLY;BYDAY=2MO"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.daysOfTheWeek)
        XCTAssertEqual(rule?.daysOfTheWeek?.first?.dayOfTheWeek, .monday)
        XCTAssertEqual(rule?.daysOfTheWeek?.first?.weekNumber, 2)
    }

    func testParseByDayLastWeek() {
        let rrule = "FREQ=MONTHLY;BYDAY=-1FR"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.daysOfTheWeek?.first?.dayOfTheWeek, .friday)
        XCTAssertEqual(rule?.daysOfTheWeek?.first?.weekNumber, -1)
    }

    // MARK: - BYMONTHDAY Tests

    func testParseByMonthDay() {
        let rrule = "FREQ=MONTHLY;BYMONTHDAY=15"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.daysOfTheMonth)
        XCTAssertEqual(rule?.daysOfTheMonth?.first?.intValue, 15)
    }

    func testParseByMonthDayMultiple() {
        let rrule = "FREQ=MONTHLY;BYMONTHDAY=1,15"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.daysOfTheMonth?.count, 2)
    }

    // MARK: - BYMONTH Tests

    func testParseByMonth() {
        let rrule = "FREQ=YEARLY;BYMONTH=7"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.monthsOfTheYear)
        XCTAssertEqual(rule?.monthsOfTheYear?.first?.intValue, 7)
    }

    // MARK: - Complex Rule Tests

    func testParseComplexRule() {
        let rrule = "FREQ=MONTHLY;INTERVAL=2;BYDAY=TU;BYSETPOS=2;COUNT=12"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .monthly)
        XCTAssertEqual(rule?.interval, 2)
        XCTAssertEqual(rule?.daysOfTheWeek?.first?.dayOfTheWeek, .tuesday)
        XCTAssertEqual(rule?.setPositions?.first?.intValue, 2)
        XCTAssertEqual(rule?.recurrenceEnd?.occurrenceCount, 12)
    }

    // MARK: - RRULE Prefix Tests

    func testParseWithRRulePrefix() {
        let rrule = "RRULE:FREQ=DAILY;COUNT=5"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .daily)
        XCTAssertEqual(rule?.recurrenceEnd?.occurrenceCount, 5)
    }

    // MARK: - Invalid Rule Tests

    func testParseInvalidFrequency() {
        let rrule = "FREQ=INVALID"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNil(rule)
    }

    func testParseMissingFrequency() {
        let rrule = "INTERVAL=2;COUNT=10"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)

        XCTAssertNil(rule)
    }

    // MARK: - Round Trip Tests

    func testRoundTripDaily() {
        let rrule = "FREQ=DAILY;INTERVAL=2;COUNT=10"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)
        XCTAssertNotNil(rule)

        let output = RecurrenceMapper.toRRule(rule!)

        XCTAssertTrue(output.contains("FREQ=DAILY"))
        XCTAssertTrue(output.contains("INTERVAL=2"))
        XCTAssertTrue(output.contains("COUNT=10"))
    }

    func testRoundTripWeeklyWithDays() {
        let rrule = "FREQ=WEEKLY;BYDAY=MO,WE,FR"
        let startDate = Date()

        let rule = RecurrenceMapper.parseRRule(rrule, startDate: startDate)
        XCTAssertNotNil(rule)

        let output = RecurrenceMapper.toRRule(rule!)

        XCTAssertTrue(output.contains("FREQ=WEEKLY"))
        XCTAssertTrue(output.contains("BYDAY="))
        // Days might be in different order
        XCTAssertTrue(output.contains("MO"))
        XCTAssertTrue(output.contains("WE"))
        XCTAssertTrue(output.contains("FR"))
    }
}
