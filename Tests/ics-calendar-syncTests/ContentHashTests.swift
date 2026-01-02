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
