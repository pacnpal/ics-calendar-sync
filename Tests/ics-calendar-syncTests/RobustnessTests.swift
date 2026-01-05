import XCTest
@testable import ics_calendar_sync

final class RobustnessTests: XCTestCase {

    // MARK: - SyncLock Tests

    func testSyncLockAcquireAndRelease() throws {
        let lock = SyncLock()

        // Should acquire successfully
        XCTAssertNoThrow(try lock.acquire())

        // Release
        lock.release()

        // Should be able to acquire again after release
        XCTAssertNoThrow(try lock.acquire())
        lock.release()
    }

    func testSyncLockPreventsDoubleAcquire() throws {
        let lock = SyncLock()

        // First acquire should succeed
        try lock.acquire()

        // Second acquire should fail with syncInProgress
        let lock2 = SyncLock()
        XCTAssertThrowsError(try lock2.acquire()) { error in
            XCTAssertTrue(error is SyncError)
            if let syncError = error as? SyncError {
                switch syncError {
                case .syncInProgress:
                    break // Expected
                default:
                    XCTFail("Expected syncInProgress error")
                }
            }
        }

        // Clean up
        lock.release()
    }

    func testSyncLockCleanupOnRelease() throws {
        let lock = SyncLock()

        try lock.acquire()
        lock.release()

        // Lock file should be removed
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lockPath = "\(home)/.config/ics-calendar-sync/.sync.lock"
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockPath))
    }

    // MARK: - Configuration Format Tests

    func testGUIConfigFormatDetection() async throws {
        // Create a temporary GUI-format config
        let guiConfig: [String: Any] = [
            "feeds": [
                [
                    "id": "test-feed-id",
                    "name": "Test Feed",
                    "icsURL": "https://example.com/calendar.ics",
                    "calendarName": "Test Calendar",
                    "isEnabled": true,
                    "deleteOrphans": true,
                    "syncInterval": 15
                ]
            ],
            "global_sync_interval": 15,
            "notifications_enabled": false
        ]

        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-gui-config.json")

        let jsonData = try JSONSerialization.data(withJSONObject: guiConfig, options: .prettyPrinted)
        try jsonData.write(to: configPath)

        defer {
            try? FileManager.default.removeItem(at: configPath)
        }

        // Load config - should detect GUI format and convert
        let configManager = ConfigurationManager.shared
        let config = try await configManager.load(from: configPath.path)

        XCTAssertEqual(config.source.url, "https://example.com/calendar.ics")
        XCTAssertEqual(config.destination.calendarName, "Test Calendar")
        XCTAssertEqual(config.sync.deleteOrphans, true)
        XCTAssertEqual(config.daemon.intervalMinutes, 15)
    }

    func testCLIConfigFormatStillWorks() async throws {
        // Create a CLI-format config
        let cliConfig: [String: Any] = [
            "source": [
                "url": "https://example.com/cli-calendar.ics"
            ],
            "destination": [
                "calendar_name": "CLI Calendar"
            ],
            "sync": [
                "delete_orphans": false
            ],
            "daemon": [
                "interval_minutes": 30
            ]
        ]

        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-cli-config.json")

        let jsonData = try JSONSerialization.data(withJSONObject: cliConfig, options: .prettyPrinted)
        try jsonData.write(to: configPath)

        defer {
            try? FileManager.default.removeItem(at: configPath)
        }

        let configManager = ConfigurationManager.shared
        let config = try await configManager.load(from: configPath.path)

        XCTAssertEqual(config.source.url, "https://example.com/cli-calendar.ics")
        XCTAssertEqual(config.destination.calendarName, "CLI Calendar")
        XCTAssertEqual(config.sync.deleteOrphans, false)
        XCTAssertEqual(config.daemon.intervalMinutes, 30)
    }

    func testGUIConfigWithNoEnabledFeeds() async throws {
        let guiConfig: [String: Any] = [
            "feeds": [
                [
                    "id": "disabled-feed",
                    "name": "Disabled Feed",
                    "icsURL": "https://example.com/disabled.ics",
                    "calendarName": "Disabled",
                    "isEnabled": false
                ]
            ],
            "global_sync_interval": 15
        ]

        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-disabled-config.json")

        let jsonData = try JSONSerialization.data(withJSONObject: guiConfig, options: .prettyPrinted)
        try jsonData.write(to: configPath)

        defer {
            try? FileManager.default.removeItem(at: configPath)
        }

        // Should still work by using the first feed (even if disabled)
        let configManager = ConfigurationManager.shared
        let config = try await configManager.load(from: configPath.path)

        XCTAssertEqual(config.source.url, "https://example.com/disabled.ics")
    }

    func testGUIConfigWithEmptyFeeds() async throws {
        let guiConfig: [String: Any] = [
            "feeds": [] as [[String: Any]],
            "global_sync_interval": 15
        ]

        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-empty-feeds-config.json")

        let jsonData = try JSONSerialization.data(withJSONObject: guiConfig, options: .prettyPrinted)
        try jsonData.write(to: configPath)

        defer {
            try? FileManager.default.removeItem(at: configPath)
        }

        let configManager = ConfigurationManager.shared

        // Should throw error for empty feeds
        do {
            _ = try await configManager.load(from: configPath.path)
            XCTFail("Should throw error for empty feeds")
        } catch {
            // Expected
            XCTAssertTrue(error.localizedDescription.contains("feeds"))
        }
    }

    // MARK: - ICS Error Tests

    func testICSErrorDescriptions() {
        let errors: [(ICSError, String)] = [
            (.emptyResponse, "empty response"),
            (.invalidResponse(429, message: "Rate limited"), "Rate limited"),
            (.invalidResponse(503, message: nil), "HTTP 503"),
            (.parseError("Invalid format"), "Invalid format"),
            (.authenticationRequired, "Authentication required")
        ]

        for (error, expectedSubstring) in errors {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(
                description.lowercased().contains(expectedSubstring.lowercased()),
                "Error '\(error)' should contain '\(expectedSubstring)', got '\(description)'"
            )
        }
    }

    func testSyncErrorDescriptions() {
        let errors: [(SyncError, String)] = [
            (.syncInProgress, "already in progress"),
            (.calendarAccessRevoked, "revoked"),
            (.stateCorrupted, "corrupted")
        ]

        for (error, expectedSubstring) in errors {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(
                description.lowercased().contains(expectedSubstring.lowercased()),
                "Error '\(error)' should contain '\(expectedSubstring)', got '\(description)'"
            )
        }
    }

    // MARK: - ICS Validation Tests

    func testICSContentValidation() async throws {
        // Valid ICS content
        let validICS = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:test@test.com
        DTSTART:20240101T090000Z
        DTEND:20240101T100000Z
        SUMMARY:Test
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSParser()
        let events = try await parser.parse(validICS)
        XCTAssertEqual(events.count, 1)
    }

    func testICSContentWithoutVCALENDAR() async throws {
        // Content without proper VCALENDAR header
        let invalidICS = """
        <html>
        <body>Not a calendar</body>
        </html>
        """

        let parser = ICSParser()
        let events = try await parser.parse(invalidICS)

        // Should return empty (no valid events)
        XCTAssertEqual(events.count, 0)
    }

    // MARK: - Sync Result Tests

    func testSyncResultHasErrors() {
        var result = SyncResult()
        XCTAssertFalse(result.hasErrors)

        result.errors.append(SyncResult.SyncEventError(uid: "test", operation: "create", message: "Error"))
        XCTAssertTrue(result.hasErrors)
    }

    func testSyncResultTotalProcessed() {
        var result = SyncResult()
        result.created = 5
        result.updated = 3
        result.deleted = 2
        result.unchanged = 10

        XCTAssertEqual(result.totalProcessed, 20)
    }

    // MARK: - Helper for cleanup

    override func tearDown() {
        super.tearDown()
        // Clean up any leftover lock files
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lockPath = "\(home)/.config/ics-calendar-sync/.sync.lock"
        try? FileManager.default.removeItem(atPath: lockPath)
    }
}
