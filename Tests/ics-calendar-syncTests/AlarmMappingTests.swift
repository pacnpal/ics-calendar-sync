import EventKit
import XCTest
@testable import ics_calendar_sync

final class AlarmMappingTests: XCTestCase {
    func testAbsoluteAndRelativeAlarmsRoundTripThroughAnUnsavedEvent() async throws {
        let events = try await ICSParser().parse("""
        BEGIN:VEVENT
        UID:round-trip
        DTSTART:20240120T160000Z
        DURATION:PT1H
        RRULE:FREQ=WEEKLY;COUNT=3
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER;VALUE=DATE-TIME:20240115T171100Z
        END:VALARM
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER;RELATED=END:-PT5M
        END:VALARM
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER:+PT15M
        END:VALARM
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER:PT0S
        END:VALARM
        END:VEVENT
        """)
        let source = try XCTUnwrap(events.first)
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        EventMapper.apply(source, to: event)

        let absolute = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-01-15T17:11:00Z"))
        let alarms = try XCTUnwrap(event.alarms)
        XCTAssertEqual(alarms.compactMap(\.absoluteDate), [absolute])
        XCTAssertEqual(alarms.filter { $0.absoluteDate == nil }.map(\.relativeOffset).sorted(), [0, 900, 3300])
        XCTAssertEqual(event.recurrenceRules?.first?.frequency, .weekly)

        let recovered = EventMapper.toICSEvent(event).alarms
        XCTAssertEqual(recovered.compactMap(\.absoluteDate), [absolute])
        let relative = recovered.filter { $0.absoluteDate == nil }
        XCTAssertEqual(relative.map(\.trigger).sorted(), [0, 900, 3300])
        XCTAssertTrue(relative.allSatisfy { $0.triggerRelation == .start })
    }

    func testEndRelativeAlarmsUseTheExclusiveAllDayEnd() async throws {
        let store = EKEventStore()
        for (end, dayCount) in [("", 1), ("DTEND;VALUE=DATE:20240312", 3)] {
            let events = try await ICSParser().parse("""
            BEGIN:VEVENT
            UID:all-day
            DTSTART;VALUE=DATE:20240309
            \(end)
            BEGIN:VALARM
            ACTION:DISPLAY
            TRIGGER;RELATED=END:-PT5M
            END:VALARM
            END:VEVENT
            """)
            let source = try XCTUnwrap(events.first)
            let event = EKEvent(eventStore: store)
            EventMapper.apply(source, to: event)
            let alarm = try XCTUnwrap(event.alarms?.first)
            let endDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: dayCount, to: source.startDate))
            XCTAssertTrue(event.isAllDay)
            XCTAssertNil(alarm.absoluteDate)
            XCTAssertEqual(source.startDate.addingTimeInterval(alarm.relativeOffset), endDate.addingTimeInterval(-300))
        }
    }

    func testEndRelativeAlarmUsesElapsedDurationAcrossSpringForward() async throws {
        let events = try await ICSParser().parse("""
        BEGIN:VEVENT
        UID:dst
        DTSTART;TZID=America/New_York:20240309T120000
        DURATION:P1D
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER;RELATED=END:+PT15M
        END:VALARM
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER;RELATED=END:-P1D
        END:VALARM
        END:VEVENT
        """)
        let source = try XCTUnwrap(events.first)
        let event = EKEvent(eventStore: EKEventStore())
        EventMapper.apply(source, to: event)
        XCTAssertEqual(source.duration, 23 * 3600)
        XCTAssertEqual(source.alarms.map(\.trigger), [900, -23 * 3600])
        XCTAssertEqual(event.alarms?.map(\.relativeOffset).sorted(), [0, 23 * 3600 + 900])
    }
}
