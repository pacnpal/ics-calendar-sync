import XCTest
@testable import ICSCalendarSyncGUI

final class FeedConfigurationTests: XCTestCase {

    // MARK: - Default Values Tests

    func testDefaultValues() {
        let feed = FeedConfiguration()

        XCTAssertNotEqual(feed.id, UUID()) // Should have a UUID
        XCTAssertEqual(feed.name, "")
        XCTAssertEqual(feed.icsURL, "")
        XCTAssertEqual(feed.calendarName, "Subscribed Events")
        XCTAssertEqual(feed.syncInterval, 15)
        XCTAssertTrue(feed.deleteOrphans)
        XCTAssertTrue(feed.isEnabled)
        XCTAssertTrue(feed.notificationsEnabled)
    }

    func testCustomInit() {
        let id = UUID()
        let feed = FeedConfiguration(
            id: id,
            name: "Work Calendar",
            icsURL: "https://example.com/work.ics",
            calendarName: "Work",
            syncInterval: 30,
            deleteOrphans: false,
            isEnabled: false,
            notificationsEnabled: false
        )

        XCTAssertEqual(feed.id, id)
        XCTAssertEqual(feed.name, "Work Calendar")
        XCTAssertEqual(feed.icsURL, "https://example.com/work.ics")
        XCTAssertEqual(feed.calendarName, "Work")
        XCTAssertEqual(feed.syncInterval, 30)
        XCTAssertFalse(feed.deleteOrphans)
        XCTAssertFalse(feed.isEnabled)
        XCTAssertFalse(feed.notificationsEnabled)
    }

    // MARK: - Display Name Tests

    func testDisplayNameWithName() {
        let feed = FeedConfiguration(name: "My Feed", calendarName: "Calendar")
        XCTAssertEqual(feed.displayName, "My Feed")
    }

    func testDisplayNameWithoutName() {
        let feed = FeedConfiguration(name: "", calendarName: "My Calendar")
        XCTAssertEqual(feed.displayName, "My Calendar")
    }

    func testDisplayNameFallback() {
        let feed = FeedConfiguration(name: "", calendarName: "")
        XCTAssertEqual(feed.displayName, "Unnamed Feed")
    }

    // MARK: - JSON Encoding/Decoding Tests

    func testEncodeAndDecode() throws {
        let original = FeedConfiguration(
            name: "Test Feed",
            icsURL: "https://test.com/cal.ics",
            calendarName: "Test Calendar",
            syncInterval: 60,
            deleteOrphans: false,
            isEnabled: true,
            notificationsEnabled: false
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FeedConfiguration.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.icsURL, decoded.icsURL)
        XCTAssertEqual(original.calendarName, decoded.calendarName)
        XCTAssertEqual(original.syncInterval, decoded.syncInterval)
        XCTAssertEqual(original.deleteOrphans, decoded.deleteOrphans)
        XCTAssertEqual(original.isEnabled, decoded.isEnabled)
        XCTAssertEqual(original.notificationsEnabled, decoded.notificationsEnabled)
    }

    func testDecodeMissingNotificationsEnabled() throws {
        // Simulate old config without notificationsEnabled field
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "Legacy Feed",
            "icsURL": "https://legacy.com/cal.ics",
            "calendarName": "Legacy",
            "syncInterval": 15,
            "deleteOrphans": true,
            "isEnabled": true
        }
        """

        let data = json.data(using: .utf8)!
        let feed = try JSONDecoder().decode(FeedConfiguration.self, from: data)

        // Should default to true when missing
        XCTAssertTrue(feed.notificationsEnabled)
        XCTAssertEqual(feed.name, "Legacy Feed")
    }

    // MARK: - Equatable Tests

    func testEquatable() {
        let id = UUID()
        let feed1 = FeedConfiguration(id: id, name: "Test", icsURL: "https://test.com")
        let feed2 = FeedConfiguration(id: id, name: "Test", icsURL: "https://test.com")

        XCTAssertEqual(feed1, feed2)
    }

    func testNotEqualDifferentID() {
        let feed1 = FeedConfiguration(name: "Test", icsURL: "https://test.com")
        let feed2 = FeedConfiguration(name: "Test", icsURL: "https://test.com")

        XCTAssertNotEqual(feed1, feed2) // Different UUIDs
    }

    // MARK: - Identifiable Tests

    func testIdentifiable() {
        let feed = FeedConfiguration()
        XCTAssertEqual(feed.id, feed.id)
    }
}
