import XCTest
@testable import ICSCalendarSyncGUI

@MainActor
final class SyncViewModelTests: XCTestCase {

    var mockFileSystem: MockFileSystem!
    var mockCLIRunner: MockCLIRunner!
    var mockLogger: MockLogger!

    override func setUp() async throws {
        mockFileSystem = MockFileSystem()
        mockCLIRunner = MockCLIRunner()
        mockLogger = MockLogger()
    }

    override func tearDown() async throws {
        mockFileSystem = nil
        mockCLIRunner = nil
        mockLogger = nil
    }

    private func createViewModel(autoLoad: Bool = false) -> SyncViewModel {
        let deps = SyncViewModelDependencies(
            configPath: "/test/gui-config.json",
            statePath: "/test/state.db",
            cliPath: "/test/ics-calendar-sync",
            cliRunner: mockCLIRunner,
            fileSystem: mockFileSystem,
            logger: mockLogger
        )
        return SyncViewModel(dependencies: deps, autoLoad: autoLoad)
    }

    // MARK: - Initialization Tests

    func testInitialState() {
        let vm = createViewModel()

        XCTAssertEqual(vm.status, .idle)
        XCTAssertNil(vm.lastSyncTime)
        XCTAssertEqual(vm.eventCount, 0)
        XCTAssertFalse(vm.isServiceRunning)
        XCTAssertNil(vm.lastError)
        XCTAssertEqual(vm.feeds.count, 0)
        XCTAssertFalse(vm.notificationsEnabled)
        XCTAssertFalse(vm.hasFeeds)
        XCTAssertEqual(vm.enabledFeeds.count, 0)
    }

    func testSyncIntervalsAvailable() {
        let vm = createViewModel()
        XCTAssertEqual(vm.syncIntervals, [5, 15, 30, 60])
    }

    // MARK: - Feed Management Tests

    func testAddFeed() {
        let vm = createViewModel()
        let feed = FeedConfiguration(name: "Test Feed", icsURL: "https://test.com")

        vm.addFeed(feed)

        XCTAssertEqual(vm.feeds.count, 1)
        XCTAssertEqual(vm.feeds[0].name, "Test Feed")
        XCTAssertTrue(vm.hasFeeds)
    }

    func testUpdateFeed() {
        let vm = createViewModel()
        var feed = FeedConfiguration(name: "Original", icsURL: "https://test.com")
        vm.addFeed(feed)

        feed.name = "Updated"
        vm.updateFeed(feed)

        XCTAssertEqual(vm.feeds.count, 1)
        XCTAssertEqual(vm.feeds[0].name, "Updated")
    }

    func testDeleteFeed() {
        let vm = createViewModel()
        let feed = FeedConfiguration(name: "To Delete", icsURL: "https://test.com")
        vm.addFeed(feed)

        XCTAssertEqual(vm.feeds.count, 1)

        vm.deleteFeed(feed)

        XCTAssertEqual(vm.feeds.count, 0)
        XCTAssertFalse(vm.hasFeeds)
    }

    func testDeleteFeedAtOffsets() {
        let vm = createViewModel()
        vm.addFeed(FeedConfiguration(name: "Feed 1", icsURL: "https://test1.com"))
        vm.addFeed(FeedConfiguration(name: "Feed 2", icsURL: "https://test2.com"))
        vm.addFeed(FeedConfiguration(name: "Feed 3", icsURL: "https://test3.com"))

        vm.deleteFeed(at: IndexSet(integer: 1))

        XCTAssertEqual(vm.feeds.count, 2)
        XCTAssertEqual(vm.feeds[0].name, "Feed 1")
        XCTAssertEqual(vm.feeds[1].name, "Feed 3")
    }

    func testToggleFeed() {
        let vm = createViewModel()
        let feed = FeedConfiguration(name: "Test", icsURL: "https://test.com", isEnabled: true)
        vm.addFeed(feed)

        XCTAssertTrue(vm.feeds[0].isEnabled)

        vm.toggleFeed(vm.feeds[0])

        XCTAssertFalse(vm.feeds[0].isEnabled)
    }

    func testEnabledFeeds() {
        let vm = createViewModel()
        vm.addFeed(FeedConfiguration(name: "Enabled 1", icsURL: "https://test1.com", isEnabled: true))
        vm.addFeed(FeedConfiguration(name: "Disabled", icsURL: "https://test2.com", isEnabled: false))
        vm.addFeed(FeedConfiguration(name: "Enabled 2", icsURL: "https://test3.com", isEnabled: true))

        XCTAssertEqual(vm.enabledFeeds.count, 2)
        XCTAssertEqual(vm.enabledFeeds[0].name, "Enabled 1")
        XCTAssertEqual(vm.enabledFeeds[1].name, "Enabled 2")
    }

    // MARK: - Menu Bar Icon Tests

    func testMenuBarIconIdle() {
        let vm = createViewModel()
        XCTAssertEqual(vm.menuBarIcon, "calendar.badge.clock")
    }

    func testMenuBarIconSyncing() {
        let vm = createViewModel()
        vm.setStatus(.syncing)
        XCTAssertEqual(vm.menuBarIcon, "arrow.triangle.2.circlepath")
    }

    func testMenuBarIconSuccess() {
        let vm = createViewModel()
        vm.setStatus(.success)
        XCTAssertEqual(vm.menuBarIcon, "checkmark.circle")
    }

    func testMenuBarIconError() {
        let vm = createViewModel()
        vm.setStatus(.error("test"))
        XCTAssertEqual(vm.menuBarIcon, "exclamationmark.triangle")
    }

    // MARK: - Load Config Tests

    func testLoadConfigNotFound() async {
        let vm = createViewModel()

        await vm.loadConfig()

        XCTAssertEqual(vm.feeds.count, 0)
        XCTAssertFalse(vm.notificationsEnabled)
    }

    func testLoadConfigSuccess() async {
        mockFileSystem.setFile("/test/gui-config.json", content: """
        {
            "feeds": [
                {
                    "id": "12345678-1234-1234-1234-123456789012",
                    "name": "Test Feed",
                    "icsURL": "https://example.com/cal.ics",
                    "calendarName": "My Calendar",
                    "syncInterval": 30,
                    "deleteOrphans": false,
                    "isEnabled": true,
                    "notificationsEnabled": true
                }
            ],
            "notifications_enabled": true,
            "global_sync_interval": 30
        }
        """)

        let vm = createViewModel()
        await vm.loadConfig()

        XCTAssertEqual(vm.feeds.count, 1)
        XCTAssertEqual(vm.feeds[0].name, "Test Feed")
        XCTAssertEqual(vm.feeds[0].icsURL, "https://example.com/cal.ics")
        XCTAssertEqual(vm.feeds[0].calendarName, "My Calendar")
        XCTAssertEqual(vm.feeds[0].syncInterval, 30)
        XCTAssertFalse(vm.feeds[0].deleteOrphans)
        XCTAssertTrue(vm.feeds[0].isEnabled)
        XCTAssertTrue(vm.feeds[0].notificationsEnabled)
        XCTAssertTrue(vm.notificationsEnabled)
    }

    func testLoadConfigInvalidJSON() async {
        mockFileSystem.setFile("/test/gui-config.json", content: "not valid json")

        let vm = createViewModel()
        await vm.loadConfig()

        XCTAssertEqual(vm.feeds.count, 0)
    }

    func testLoadConfigMultipleFeeds() async {
        mockFileSystem.setFile("/test/gui-config.json", content: """
        {
            "feeds": [
                {
                    "id": "11111111-1111-1111-1111-111111111111",
                    "name": "Feed 1",
                    "icsURL": "https://test1.com",
                    "calendarName": "Cal1",
                    "syncInterval": 15,
                    "deleteOrphans": true,
                    "isEnabled": true,
                    "notificationsEnabled": true
                },
                {
                    "id": "22222222-2222-2222-2222-222222222222",
                    "name": "Feed 2",
                    "icsURL": "https://test2.com",
                    "calendarName": "Cal2",
                    "syncInterval": 60,
                    "deleteOrphans": false,
                    "isEnabled": false,
                    "notificationsEnabled": false
                }
            ],
            "notifications_enabled": false
        }
        """)

        let vm = createViewModel()
        await vm.loadConfig()

        XCTAssertEqual(vm.feeds.count, 2)
        XCTAssertEqual(vm.feeds[0].name, "Feed 1")
        XCTAssertEqual(vm.feeds[1].name, "Feed 2")
        XCTAssertTrue(vm.feeds[0].isEnabled)
        XCTAssertFalse(vm.feeds[1].isEnabled)
        XCTAssertFalse(vm.notificationsEnabled)
    }

    // MARK: - Save Config Tests

    func testSaveConfigCreatesFile() async {
        let vm = createViewModel()
        vm.addFeed(FeedConfiguration(
            name: "Test Feed",
            icsURL: "https://test.com/calendar.ics",
            calendarName: "Test Calendar",
            syncInterval: 60,
            deleteOrphans: false
        ))
        vm.notificationsEnabled = true

        await vm.saveConfig()

        XCTAssertNil(vm.lastError)

        let savedContent = mockFileSystem.getFile("/test/gui-config.json")
        XCTAssertNotNil(savedContent)

        if let content = savedContent {
            XCTAssertTrue(content.contains("Test Feed"))
            XCTAssertTrue(content.contains("test.com"))
            XCTAssertTrue(content.contains("Test Calendar"))
        }
    }

    func testSaveConfigMultipleFeeds() async {
        let vm = createViewModel()
        vm.addFeed(FeedConfiguration(name: "Feed 1", icsURL: "https://test1.com"))
        vm.addFeed(FeedConfiguration(name: "Feed 2", icsURL: "https://test2.com"))
        vm.notificationsEnabled = true

        await vm.saveConfig()

        let savedContent = mockFileSystem.getFile("/test/gui-config.json")
        XCTAssertNotNil(savedContent)

        if let content = savedContent {
            XCTAssertTrue(content.contains("Feed 1"))
            XCTAssertTrue(content.contains("Feed 2"))
            XCTAssertTrue(content.contains("notifications_enabled"))
        }
    }

    // MARK: - Status Description Tests

    func testStatusDescriptionIdle() {
        let vm = createViewModel()
        XCTAssertEqual(vm.statusDescription, "Ready")
    }

    func testStatusDescriptionSyncing() {
        let vm = createViewModel()
        vm.setStatus(.syncing)
        XCTAssertEqual(vm.statusDescription, "Syncing...")
    }

    func testStatusDescriptionSuccess() {
        let vm = createViewModel()
        vm.setStatus(.success)
        XCTAssertEqual(vm.statusDescription, "Sync complete")
    }

    func testStatusDescriptionError() {
        let vm = createViewModel()
        vm.setStatus(.error("Network timeout"))
        XCTAssertEqual(vm.statusDescription, "Error: Network timeout")
    }

    func testStatusDescriptionErrorTruncated() {
        let vm = createViewModel()
        let longError = String(repeating: "a", count: 100)
        vm.setStatus(.error(longError))

        XCTAssertTrue(vm.statusDescription.count < 70)
        XCTAssertTrue(vm.statusDescription.hasSuffix("..."))
    }

    // MARK: - Last Sync Description Tests

    func testLastSyncDescriptionNever() {
        let vm = createViewModel()
        XCTAssertEqual(vm.lastSyncDescription, "Never")
    }

    func testLastSyncDescriptionRecent() {
        let vm = createViewModel()
        vm.lastSyncTime = Date()

        let description = vm.lastSyncDescription
        XCTAssertNotEqual(description, "Never")
    }

    // MARK: - Sync Now Tests

    func testSyncNowWithoutFeeds() async {
        let vm = createViewModel()

        await vm.syncNow()

        XCTAssertNotNil(vm.lastError)
        XCTAssertEqual(vm.lastError, "Please add at least one feed")
    }

    func testSyncNowSuccess() async {
        await mockCLIRunner.setResponse(for: "sync", result: .success)

        let vm = createViewModel()
        vm.addFeed(FeedConfiguration(name: "Test", icsURL: "https://test.com", isEnabled: true))

        let syncTask = Task {
            await vm.syncNow()
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        syncTask.cancel()

        let history = await mockCLIRunner.getCallHistory()
        XCTAssertTrue(history.contains { $0.first == "sync" })
    }

    func testSyncNowFailure() async {
        await mockCLIRunner.setResponse(for: "sync", result: .failure("Network error"))

        let vm = createViewModel()
        vm.addFeed(FeedConfiguration(name: "Test", icsURL: "https://test.com", isEnabled: true))

        await vm.syncNow()

        XCTAssertEqual(vm.status, .error("Network error"))
        XCTAssertEqual(vm.lastError, "Network error")
    }

    func testSyncNowOnlyEnabledFeeds() async {
        await mockCLIRunner.setResponse(for: "sync", result: .success)

        let vm = createViewModel()
        vm.addFeed(FeedConfiguration(name: "Enabled", icsURL: "https://enabled.com", isEnabled: true))
        vm.addFeed(FeedConfiguration(name: "Disabled", icsURL: "https://disabled.com", isEnabled: false))

        let syncTask = Task {
            await vm.syncNow()
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        syncTask.cancel()

        let history = await mockCLIRunner.getCallHistory()
        // Should only have synced one feed (the enabled one)
        let syncCalls = history.filter { $0.first == "sync" }
        XCTAssertEqual(syncCalls.count, 1)
    }

    // MARK: - Service Control Tests

    // Note: Service control now uses direct launchctl calls instead of CLI commands.
    // These tests verify the state management and logging behavior.

    func testCheckServiceStatusInitial() async {
        // In test environment with no LaunchAgent installed, service should be not installed
        let vm = createViewModel()
        await vm.checkServiceStatus()

        // Service should not be installed in test environment
        XCTAssertFalse(vm.isServiceInstalled)
    }

    func testGetServiceStatusNotInstalled() async {
        let vm = createViewModel()
        let status = await vm.getServiceStatus()

        XCTAssertEqual(status, .notInstalled)
    }

    func testStopServiceWithoutInstall() async {
        // When service is not installed, stopService should be a no-op
        let vm = createViewModel()
        XCTAssertFalse(vm.isServiceInstalled)

        await vm.stopService()

        // Should complete without error since it's not installed
        XCTAssertFalse(vm.isServiceRunning)
    }

    func testServiceStatusProperties() async {
        let vm = createViewModel()

        // Initial state should have service not installed
        XCTAssertFalse(vm.isServiceInstalled)
        XCTAssertFalse(vm.isServiceRunning)
    }

    func testInstallServiceWithoutCLI() async {
        // When CLI doesn't exist, install should fail with error
        let vm = createViewModel()

        let success = await vm.installService()

        XCTAssertFalse(success)
        XCTAssertNotNil(vm.lastError)
        XCTAssertTrue(vm.lastError?.contains("CLI not found") ?? false)
    }

    func testAutoInstallServiceIfNeeded() async {
        // When CLI doesn't exist, auto-install should skip silently
        let vm = createViewModel()

        await vm.autoInstallServiceIfNeeded()

        // Should not set error since auto-install is best-effort
        XCTAssertFalse(vm.isServiceInstalled)
    }

    // MARK: - Timer Tests

    func testStartRefreshTimer() {
        let vm = createViewModel()

        vm.startRefreshTimer()
        vm.startRefreshTimer() // Should not create a second timer

        vm.stopRefreshTimer()
    }

    func testStopRefreshTimer() {
        let vm = createViewModel()

        vm.startRefreshTimer()
        vm.stopRefreshTimer()
        vm.stopRefreshTimer() // Should be safe to call multiple times
    }

    // MARK: - Logging Tests

    func testLoggingOnInitialization() {
        _ = createViewModel()

        let messages = mockLogger.messages
        XCTAssertTrue(messages.contains { $0.level == "INFO" && $0.message.contains("initialized") })
    }

    func testLoggingOnConfigLoad() async {
        mockFileSystem.setFile("/test/gui-config.json", content: "{}")

        let vm = createViewModel()
        await vm.loadConfig()

        let messages = mockLogger.messages
        XCTAssertTrue(messages.contains { $0.level == "DEBUG" && $0.message.contains("Loading configuration") })
    }

    func testLoggingOnConfigSave() async {
        let vm = createViewModel()
        await vm.saveConfig()

        let messages = mockLogger.messages
        XCTAssertTrue(messages.contains { $0.level == "INFO" && $0.message.contains("Saving configuration") })
    }

    func testLoggingOnFeedAdd() {
        let vm = createViewModel()
        vm.addFeed(FeedConfiguration(name: "Test Feed", icsURL: "https://test.com"))

        let messages = mockLogger.messages
        XCTAssertTrue(messages.contains { $0.level == "INFO" && $0.message.contains("Added feed") })
    }

    func testLoggingOnFeedDelete() {
        let vm = createViewModel()
        let feed = FeedConfiguration(name: "Test Feed", icsURL: "https://test.com")
        vm.addFeed(feed)
        mockLogger.clear()

        vm.deleteFeed(feed)

        let messages = mockLogger.messages
        XCTAssertTrue(messages.contains { $0.level == "INFO" && $0.message.contains("Deleted feed") })
    }

    // MARK: - Notification Setting Tests

    func testGlobalNotificationsDefault() {
        let vm = createViewModel()
        XCTAssertFalse(vm.notificationsEnabled)
    }

    func testGlobalNotificationsCanBeSet() {
        let vm = createViewModel()
        vm.notificationsEnabled = true
        XCTAssertTrue(vm.notificationsEnabled)
    }

    func testPerFeedNotificationsDefault() {
        let vm = createViewModel()
        let feed = FeedConfiguration(name: "Test", icsURL: "https://test.com")
        vm.addFeed(feed)

        XCTAssertTrue(vm.feeds[0].notificationsEnabled) // Default is true
    }

    func testPerFeedNotificationsCanBeToggled() {
        let vm = createViewModel()
        var feed = FeedConfiguration(name: "Test", icsURL: "https://test.com", notificationsEnabled: true)
        vm.addFeed(feed)

        feed.notificationsEnabled = false
        vm.updateFeed(feed)

        XCTAssertFalse(vm.feeds[0].notificationsEnabled)
    }
}
