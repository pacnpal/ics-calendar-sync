import XCTest
@testable import ICSCalendarSyncGUI

final class GUIConfigurationTests: XCTestCase {

    // MARK: - Default Values Tests

    func testDefaultConfiguration() {
        let config = GUIConfiguration()

        XCTAssertEqual(config.feeds.count, 0)
        XCTAssertFalse(config.notificationsEnabled)
        XCTAssertEqual(config.globalSyncInterval, 15)
    }

    // MARK: - JSON Decoding Tests

    func testDecodeFullConfig() throws {
        let json = """
        {
            "feeds": [
                {
                    "id": "12345678-1234-1234-1234-123456789012",
                    "name": "Work Calendar",
                    "icsURL": "https://example.com/work.ics",
                    "calendarName": "Work",
                    "syncInterval": 30,
                    "deleteOrphans": true,
                    "isEnabled": true,
                    "notificationsEnabled": true
                },
                {
                    "id": "87654321-4321-4321-4321-210987654321",
                    "name": "Personal",
                    "icsURL": "https://example.com/personal.ics",
                    "calendarName": "Personal",
                    "syncInterval": 60,
                    "deleteOrphans": false,
                    "isEnabled": false,
                    "notificationsEnabled": false
                }
            ],
            "notifications_enabled": true,
            "global_sync_interval": 30
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(GUIConfiguration.self, from: data)

        XCTAssertEqual(config.feeds.count, 2)
        XCTAssertTrue(config.notificationsEnabled)
        XCTAssertEqual(config.globalSyncInterval, 30)

        XCTAssertEqual(config.feeds[0].name, "Work Calendar")
        XCTAssertEqual(config.feeds[0].icsURL, "https://example.com/work.ics")
        XCTAssertEqual(config.feeds[0].calendarName, "Work")
        XCTAssertEqual(config.feeds[0].syncInterval, 30)
        XCTAssertTrue(config.feeds[0].deleteOrphans)
        XCTAssertTrue(config.feeds[0].isEnabled)
        XCTAssertTrue(config.feeds[0].notificationsEnabled)

        XCTAssertEqual(config.feeds[1].name, "Personal")
        XCTAssertFalse(config.feeds[1].isEnabled)
        XCTAssertFalse(config.feeds[1].notificationsEnabled)
    }

    func testDecodeEmptyConfig() throws {
        let json = "{}"

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(GUIConfiguration.self, from: data)

        XCTAssertEqual(config.feeds.count, 0)
        XCTAssertFalse(config.notificationsEnabled)
        XCTAssertEqual(config.globalSyncInterval, 15)
    }

    func testDecodePartialConfig() throws {
        let json = """
        {
            "notifications_enabled": true
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(GUIConfiguration.self, from: data)

        XCTAssertEqual(config.feeds.count, 0)
        XCTAssertTrue(config.notificationsEnabled)
        XCTAssertEqual(config.globalSyncInterval, 15)
    }

    func testDecodeConfigWithEmptyFeeds() throws {
        let json = """
        {
            "feeds": [],
            "notifications_enabled": false,
            "global_sync_interval": 60
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(GUIConfiguration.self, from: data)

        XCTAssertEqual(config.feeds.count, 0)
        XCTAssertFalse(config.notificationsEnabled)
        XCTAssertEqual(config.globalSyncInterval, 60)
    }

    // MARK: - Init with Parameters Tests

    func testInitWithParameters() {
        let feed1 = FeedConfiguration(name: "Feed 1", icsURL: "https://test1.com")
        let feed2 = FeedConfiguration(name: "Feed 2", icsURL: "https://test2.com")

        let config = GUIConfiguration(
            feeds: [feed1, feed2],
            notificationsEnabled: true,
            globalSyncInterval: 45
        )

        XCTAssertEqual(config.feeds.count, 2)
        XCTAssertTrue(config.notificationsEnabled)
        XCTAssertEqual(config.globalSyncInterval, 45)
        XCTAssertEqual(config.feeds[0].name, "Feed 1")
        XCTAssertEqual(config.feeds[1].name, "Feed 2")
    }

    // MARK: - Equatable Tests

    func testConfigEquatable() {
        let feed = FeedConfiguration(name: "Test")

        let config1 = GUIConfiguration(feeds: [feed], notificationsEnabled: true, globalSyncInterval: 15)
        let config2 = GUIConfiguration(feeds: [feed], notificationsEnabled: true, globalSyncInterval: 15)

        XCTAssertEqual(config1, config2)
    }

    func testConfigNotEqualDifferentNotifications() {
        let config1 = GUIConfiguration(feeds: [], notificationsEnabled: true, globalSyncInterval: 15)
        let config2 = GUIConfiguration(feeds: [], notificationsEnabled: false, globalSyncInterval: 15)

        XCTAssertNotEqual(config1, config2)
    }

    func testConfigNotEqualDifferentInterval() {
        let config1 = GUIConfiguration(feeds: [], notificationsEnabled: true, globalSyncInterval: 15)
        let config2 = GUIConfiguration(feeds: [], notificationsEnabled: true, globalSyncInterval: 30)

        XCTAssertNotEqual(config1, config2)
    }
}
