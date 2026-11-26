import XCTest
@testable import ics_calendar_sync

final class ContentHashTests: XCTestCase {

    // MARK: - Basic Hash Tests

    func testHashIsConsistent() {
        let event = createTestEvent()

        let hash1 = ContentHash.calculate(for: event)
        let hash2 = ContentHash.calculate(for: event)

        XCTAssertEqual(hash1, hash2)
    }

    func testDifferentEventsHaveDifferentHashes() {
        let event1 = createTestEvent(uid: "event-1", summary: "Event 1")
        let event2 = createTestEvent(uid: "event-2", summary: "Event 2")

        let hash1 = ContentHash.calculate(for: event1)
        let hash2 = ContentHash.calculate(for: event2)

        XCTAssertNotEqual(hash1, hash2)
    }

    func testHashChangesWithSummary() {
        let event1 = createTestEvent(summary: "Original Title")
        let event2 = createTestEvent(summary: "Updated Title")

        let hash1 = ContentHash.calculate(for: event1)
        let hash2 = ContentHash.calculate(for: event2)

        XCTAssertNotEqual(hash1, hash2)
    }

    func testHashChangesWithDescription() {
        let event1 = createTestEvent(description: "Original description")
        let event2 = createTestEvent(description: "Updated description")

        let hash1 = ContentHash.calculate(for: event1)
        let hash2 = ContentHash.calculate(for: event2)

        XCTAssertNotEqual(hash1, hash2)
    }

    func testHashChangesWithLocation() {
        let event1 = createTestEvent(location: "Room A")
        let event2 = createTestEvent(location: "Room B")

        let hash1 = ContentHash.calculate(for: event1)
        let hash2 = ContentHash.calculate(for: event2)

        XCTAssertNotEqual(hash1, hash2)
    }

    func testHashChangesWithDates() {
        let date1 = Date()
        let date2 = date1.addingTimeInterval(3600)

        let event1 = createTestEvent(startDate: date1)
        let event2 = createTestEvent(startDate: date2)

        let hash1 = ContentHash.calculate(for: event1)
        let hash2 = ContentHash.calculate(for: event2)

        XCTAssertNotEqual(hash1, hash2)
    }

    func testHashChangesWithAllDayFlag() {
        let event1 = createTestEvent(isAllDay: false)
        let event2 = createTestEvent(isAllDay: true)

        let hash1 = ContentHash.calculate(for: event1)
        let hash2 = ContentHash.calculate(for: event2)

        XCTAssertNotEqual(hash1, hash2)
    }

    func testLegacyAlarmHashes() {
        var event = createTestEvent(startDate: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(ContentHash.calculate(for: event),
                       "5a92dfbedb48e913305bbdc48ececadea651a223a5daea95ad6eeb52dd1b1f8b")

        event.alarms = [ICSAlarm(action: .display, trigger: -900, triggerRelation: .start)]
        XCTAssertEqual(ContentHash.calculate(for: event),
                       "3a9c4db7a9671c12f69875c16159d38aa4d713e293f50bd2bba499dc78e6a73a")

        // v2.1.0 retains source order when start-relative offsets tie.
        event.alarms[0].description = "Z"
        event.alarms.append(ICSAlarm(action: .audio, trigger: -900, triggerRelation: .start, description: "A"))
        XCTAssertEqual(ContentHash.calculate(for: event),
                       "a5fea800b1e88488cedeb1fb64244140ae38d69e6854bd7e09c96067a027ac20")
    }

    func testHashDistinguishesAlarmTimesAndAnchors() {
        let start = Date(timeIntervalSince1970: 0)
        var event = createTestEvent(startDate: start)
        let alarms = [
            ICSAlarm(action: .display, trigger: 0, triggerRelation: .start),
            ICSAlarm(action: .display, trigger: 0, triggerRelation: .end),
            ICSAlarm(action: .display, trigger: 0, triggerRelation: .start, absoluteDate: start),
            ICSAlarm(action: .display, trigger: 0, triggerRelation: .start, absoluteDate: start.addingTimeInterval(1))
        ]
        let hashes = alarms.map { alarm in
            event.alarms = [alarm]
            return ContentHash.calculate(for: event)
        }
        XCTAssertEqual(Set(hashes).count, 4)

        event.alarms = alarms
        let hash = ContentHash.calculate(for: event)
        event.alarms.reverse()
        XCTAssertEqual(ContentHash.calculate(for: event), hash)
    }

    // MARK: - Hash Format Tests

    func testHashIsHexString() {
        let event = createTestEvent()
        let hash = ContentHash.calculate(for: event)

        // SHA256 produces 64 hex characters
        XCTAssertEqual(hash.count, 64)

        // All characters should be hex
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(hash.unicodeScalars.allSatisfy { hexChars.contains($0) })
    }

    // MARK: - Short Hash Tests

    func testShortHash() {
        let event = createTestEvent()
        let shortHash = ContentHash.shortHash(for: event)

        XCTAssertEqual(shortHash.count, 8)

        // Short hash should be prefix of full hash
        let fullHash = ContentHash.calculate(for: event)
        XCTAssertTrue(fullHash.hasPrefix(shortHash))
    }

    // MARK: - Equality Tests

    func testAreEqualWithSameEvents() {
        let event1 = createTestEvent()
        let event2 = createTestEvent()

        XCTAssertTrue(ContentHash.areEqual(event1, event2))
    }

    func testAreEqualWithDifferentEvents() {
        let event1 = createTestEvent(summary: "Event 1")
        let event2 = createTestEvent(summary: "Event 2")

        XCTAssertFalse(ContentHash.areEqual(event1, event2))
    }

    // MARK: - Helper Methods

    private func createTestEvent(
        uid: String = "test-uid",
        summary: String? = "Test Event",
        description: String? = nil,
        location: String? = nil,
        startDate: Date = Date(),
        endDate: Date? = nil,
        isAllDay: Bool = false
    ) -> ICSEvent {
        ICSEvent(
            uid: uid,
            summary: summary,
            description: description,
            location: location,
            url: nil,
            startDate: startDate,
            endDate: endDate ?? startDate.addingTimeInterval(3600),
            isAllDay: isAllDay,
            sequence: 0,
            lastModified: nil,
            dateStamp: nil,
            recurrenceRule: nil,
            exceptionDates: [],
            recurrenceDates: [],
            alarms: [],
            status: nil,
            transparency: nil,
            organizer: nil,
            attendees: [],
            categories: [],
            priority: nil,
            rawData: "",
            timeZone: nil
        )
    }
}
