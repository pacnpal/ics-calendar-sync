import XCTest
@testable import ics_calendar_sync

final class ICSParserTests: XCTestCase {

    // MARK: - Simple Event Tests

    func testParseSimpleEvent() async throws {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:test-event-001@test.local
        DTSTAMP:20240101T120000Z
        DTSTART:20240115T090000Z
        DTEND:20240115T100000Z
        SUMMARY:Test Event
        DESCRIPTION:Test description
        LOCATION:Test Location
        SEQUENCE:0
        STATUS:CONFIRMED
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)

        let event = events[0]
        XCTAssertEqual(event.uid, "test-event-001@test.local")
        XCTAssertEqual(event.summary, "Test Event")
        XCTAssertEqual(event.description, "Test description")
        XCTAssertEqual(event.location, "Test Location")
        XCTAssertEqual(event.sequence, 0)
        XCTAssertEqual(event.status, .confirmed)
        XCTAssertFalse(event.isAllDay)
    }

    func testParseMultipleEvents() async throws {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:event-001@test.local
        DTSTART:20240115T090000Z
        DTEND:20240115T100000Z
        SUMMARY:Event 1
        END:VEVENT
        BEGIN:VEVENT
        UID:event-002@test.local
        DTSTART:20240116T090000Z
        DTEND:20240116T100000Z
        SUMMARY:Event 2
        END:VEVENT
        BEGIN:VEVENT
        UID:event-003@test.local
        DTSTART:20240117T090000Z
        DTEND:20240117T100000Z
        SUMMARY:Event 3
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].uid, "event-001@test.local")
        XCTAssertEqual(events[1].uid, "event-002@test.local")
        XCTAssertEqual(events[2].uid, "event-003@test.local")
    }

    // MARK: - All-Day Event Tests

    func testParseAllDayEvent() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:allday-001@test.local
        DTSTART;VALUE=DATE:20240120
        DTEND;VALUE=DATE:20240121
        SUMMARY:All Day Event
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isAllDay)
        XCTAssertEqual(events[0].summary, "All Day Event")
    }

    func testParseMultiDayEvent() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:multiday-001@test.local
        DTSTART;VALUE=DATE:20240301
        DTEND;VALUE=DATE:20240306
        SUMMARY:Five Day Event
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isAllDay)

        // End date should be 5 days after start
        let days = Calendar.current.dateComponents([.day], from: events[0].startDate, to: events[0].endDate).day
        XCTAssertEqual(days, 5)
    }

    // MARK: - Recurring Event Tests

    func testParseRecurringEvent() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:recurring-001@test.local
        DTSTART:20240101T090000Z
        DTEND:20240101T100000Z
        SUMMARY:Daily Standup
        RRULE:FREQ=DAILY;COUNT=10
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)
        XCTAssertNotNil(events[0].recurrenceRule)
        XCTAssertEqual(events[0].recurrenceRule, "FREQ=DAILY;COUNT=10")
        XCTAssertTrue(events[0].isRecurring)
    }

    func testParseWeeklyRecurrence() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:weekly-001@test.local
        DTSTART:20240108T140000Z
        DTEND:20240108T150000Z
        SUMMARY:Weekly Meeting
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20240331T000000Z
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)
        XCTAssertNotNil(events[0].recurrenceRule)
        XCTAssertTrue(events[0].recurrenceRule!.contains("WEEKLY"))
        XCTAssertTrue(events[0].recurrenceRule!.contains("BYDAY=MO,WE,FR"))
    }

    // MARK: - Timezone Tests

    func testParseEventWithTimezone() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:tz-001@test.local
        DTSTART;TZID=America/New_York:20240115T090000
        DTEND;TZID=America/New_York:20240115T100000
        SUMMARY:NYC Meeting
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].timeZone?.identifier, "America/New_York")
    }

    func testParseUTCEvent() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:utc-001@test.local
        DTSTART:20240115T180000Z
        DTEND:20240115T190000Z
        SUMMARY:UTC Event
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)
        // UTC events should parse correctly
        XCTAssertNotNil(events[0].startDate)
    }

    // MARK: - Special Character Tests

    func testParseEscapedCharacters() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:escaped-001@test.local
        DTSTART:20240115T090000Z
        DTEND:20240115T100000Z
        SUMMARY:Meeting\\, Important
        DESCRIPTION:Line 1\\nLine 2\\nLine 3
        LOCATION:Room 101\\; Building A
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].summary, "Meeting, Important")
        XCTAssertEqual(events[0].description, "Line 1\nLine 2\nLine 3")
        XCTAssertEqual(events[0].location, "Room 101; Building A")
    }

    // MARK: - Line Folding Tests

    func testParseLineFolding() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:folded-001@test.local
        DTSTART:20240115T090000Z
        DTEND:20240115T100000Z
        SUMMARY:This is a very long summary that needs to be folded across
         multiple lines according to the iCalendar specification
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].summary!.contains("very long summary"))
        XCTAssertTrue(events[0].summary!.contains("iCalendar specification"))
    }

    // MARK: - Missing UID Tests

    func testMissingUIDThrowsError() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART:20240115T090000Z
        DTEND:20240115T100000Z
        SUMMARY:Event Without UID
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        // Parser should skip invalid events
        XCTAssertEqual(events.count, 0)
    }

    // MARK: - Alarm Tests

    func testParseEventWithAlarm() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:alarm-001@test.local
        DTSTART:20240115T090000Z
        DTEND:20240115T100000Z
        SUMMARY:Event with Alarm
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER:-PT15M
        DESCRIPTION:15 minutes before
        END:VALARM
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].alarms.count, 1)
        XCTAssertEqual(events[0].alarms[0].action, .display)
        XCTAssertEqual(events[0].alarms[0].trigger, -15 * 60) // -15 minutes in seconds
    }

    // MARK: - Duration Tests

    func testParseEventWithDuration() async throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:duration-001@test.local
        DTSTART:20240115T090000Z
        DURATION:PT2H30M
        SUMMARY:2.5 Hour Event
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(ics)

        XCTAssertEqual(events.count, 1)

        // End should be 2.5 hours after start
        let duration = events[0].endDate.timeIntervalSince(events[0].startDate)
        XCTAssertEqual(duration, 2.5 * 60 * 60, accuracy: 1)
    }

    // MARK: - Status Tests

    func testParseEventStatus() async throws {
        let tentative = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:status-001@test.local
        DTSTART:20240115T090000Z
        DTEND:20240115T100000Z
        SUMMARY:Tentative Event
        STATUS:TENTATIVE
        END:VEVENT
        END:VCALENDAR
        """

        let cancelled = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:status-002@test.local
        DTSTART:20240115T090000Z
        DTEND:20240115T100000Z
        SUMMARY:Cancelled Event
        STATUS:CANCELLED
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()

        let tentativeEvents = try await parser.parse(tentative)
        XCTAssertEqual(tentativeEvents[0].status, .tentative)

        let cancelledEvents = try await parser.parse(cancelled)
        XCTAssertEqual(cancelledEvents[0].status, .cancelled)
    }

    // MARK: - Transparency Tests

    func testParseTransparency() async throws {
        let transparent = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:transp-001@test.local
        DTSTART:20240115T090000Z
        DTEND:20240115T100000Z
        SUMMARY:Free Time
        TRANSP:TRANSPARENT
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(transparent)

        XCTAssertEqual(events[0].transparency, .transparent)
    }
}
