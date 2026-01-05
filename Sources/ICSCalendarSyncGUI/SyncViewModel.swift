import Foundation
import SwiftUI
import SQLite
import EventKit
import UserNotifications
import os.log

// MARK: - Calendar Info

struct CalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let color: CGColor?
    let source: String

    init(from calendar: EKCalendar) {
        self.id = calendar.calendarIdentifier
        self.title = calendar.title
        self.color = calendar.cgColor
        self.source = calendar.source.title
    }

    init(title: String) {
        self.id = title
        self.title = title
        self.color = nil
        self.source = ""
    }
}

// MARK: - Notification Manager

@MainActor
class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let logger = GUILogger.shared

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }

    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func sendSyncSuccessNotification(feedName: String, eventCount: Int) async {
        let status = await checkAuthorizationStatus()
        guard status == .authorized else {
            logger.debug("Notifications not authorized, skipping")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Sync Complete"
        content.body = "\(feedName): \(eventCount) events synced"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await center.add(request)
            logger.debug("Sent sync success notification for \(feedName)")
        } catch {
            logger.error("Failed to send notification: \(error.localizedDescription)")
        }
    }

    func sendSyncErrorNotification(feedName: String, error: String) async {
        let status = await checkAuthorizationStatus()
        guard status == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Sync Failed"
        content.body = "\(feedName): \(error)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            logger.debug("Sent sync error notification for \(feedName)")
        } catch {
            logger.error("Failed to send notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - Feed Configuration

struct FeedConfiguration: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var icsURL: String
    var calendarName: String
    var syncInterval: Int
    var deleteOrphans: Bool
    var isEnabled: Bool
    var notificationsEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        icsURL: String = "",
        calendarName: String = "Subscribed Events",
        syncInterval: Int = 15,
        deleteOrphans: Bool = true,
        isEnabled: Bool = true,
        notificationsEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icsURL = icsURL
        self.calendarName = calendarName
        self.syncInterval = syncInterval
        self.deleteOrphans = deleteOrphans
        self.isEnabled = isEnabled
        self.notificationsEnabled = notificationsEnabled
    }

    // Custom decoding to handle missing notificationsEnabled field (migration)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icsURL = try container.decode(String.self, forKey: .icsURL)
        calendarName = try container.decode(String.self, forKey: .calendarName)
        syncInterval = try container.decode(Int.self, forKey: .syncInterval)
        deleteOrphans = try container.decode(Bool.self, forKey: .deleteOrphans)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
    }

    var displayName: String {
        if !name.isEmpty { return name }
        if !calendarName.isEmpty { return calendarName }
        return "Unnamed Feed"
    }
}

// MARK: - GUI Configuration (Multi-Feed)

struct GUIConfiguration: Codable, Equatable {
    var feeds: [FeedConfiguration]
    var notificationsEnabled: Bool
    var globalSyncInterval: Int
    var defaultCalendar: String

    init() {
        feeds = []
        notificationsEnabled = false
        globalSyncInterval = 15
        defaultCalendar = ""
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feeds = try container.decodeIfPresent([FeedConfiguration].self, forKey: .feeds) ?? []
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        globalSyncInterval = try container.decodeIfPresent(Int.self, forKey: .globalSyncInterval) ?? 15
        defaultCalendar = try container.decodeIfPresent(String.self, forKey: .defaultCalendar) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case feeds
        case notificationsEnabled = "notifications_enabled"
        case globalSyncInterval = "global_sync_interval"
        case defaultCalendar = "default_calendar"
    }
}

// MARK: - Legacy Configuration (for migration)

struct LegacyConfiguration: Codable {
    var source: SourceConfig?
    var destination: DestinationConfig?
    var sync: SyncConfig?
    var daemon: DaemonConfig?
    var notifications: NotificationConfig?

    struct SourceConfig: Codable {
        var url: String?
    }

    struct DestinationConfig: Codable {
        var calendarName: String?
        enum CodingKeys: String, CodingKey {
            case calendarName = "calendar_name"
        }
    }

    struct SyncConfig: Codable {
        var deleteOrphans: Bool?
        enum CodingKeys: String, CodingKey {
            case deleteOrphans = "delete_orphans"
        }
    }

    struct DaemonConfig: Codable {
        var intervalMinutes: Int?
        enum CodingKeys: String, CodingKey {
            case intervalMinutes = "interval_minutes"
        }
    }

    struct NotificationConfig: Codable {
        var enabled: Bool?
    }
}

// MARK: - Sync Status

enum SyncStatus: Equatable {
    case idle
    case syncing
    case success
    case error(String)

    var icon: String {
        switch self {
        case .idle: return "calendar.badge.clock"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }
}

// MARK: - GUILogger Protocol

protocol GUILoggerProtocol: Sendable {
    func debug(_ message: String, file: String, line: Int)
    func info(_ message: String, file: String, line: Int)
    func warning(_ message: String, file: String, line: Int)
    func error(_ message: String, file: String, line: Int)
}

extension GUILoggerProtocol {
    func debug(_ message: String, file: String = #file, line: Int = #line) {
        debug(message, file: file, line: line)
    }
    func info(_ message: String, file: String = #file, line: Int = #line) {
        info(message, file: file, line: line)
    }
    func warning(_ message: String, file: String = #file, line: Int = #line) {
        warning(message, file: file, line: line)
    }
    func error(_ message: String, file: String = #file, line: Int = #line) {
        error(message, file: file, line: line)
    }
}

// MARK: - GUILogger

final class GUILogger: GUILoggerProtocol, @unchecked Sendable {
    static let shared = GUILogger()

    private let osLog: OSLog
    private let lock = NSLock()
    private var logFileHandle: FileHandle?
    let logPath: String

    private init() {
        osLog = OSLog(subsystem: "com.ics-calendar-sync.gui", category: "general")

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let logDir = "\(home)/Library/Logs/ics-calendar-sync"
        logPath = "\(logDir)/gui.log"

        let fm = FileManager.default
        if !fm.fileExists(atPath: logDir) {
            try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil)
        }
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            logFileHandle = handle
        }
    }

    func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(level: "DEBUG", message: message, file: file, line: line)
    }

    func info(_ message: String, file: String = #file, line: Int = #line) {
        log(level: "INFO", message: message, file: file, line: line)
    }

    func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(level: "WARN", message: message, file: file, line: line)
    }

    func error(_ message: String, file: String = #file, line: Int = #line) {
        log(level: "ERROR", message: message, file: file, line: line)
    }

    private func log(level: String, message: String, file: String, line: Int) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logLine = "[\(timestamp)] \(level) [\(fileName):\(line)] \(message)\n"

        os_log("%{public}@", log: osLog, type: level == "ERROR" ? .error : .info, message)

        lock.withLock {
            if let data = logLine.data(using: .utf8) {
                logFileHandle?.write(data)
                try? logFileHandle?.synchronize()
            }
        }
    }
}

// MARK: - Mock Logger for Testing

final class MockLogger: GUILoggerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [(level: String, message: String)] = []

    var messages: [(level: String, message: String)] {
        lock.withLock { _messages }
    }

    func debug(_ message: String, file: String = #file, line: Int = #line) {
        lock.withLock { _messages.append(("DEBUG", message)) }
    }

    func info(_ message: String, file: String = #file, line: Int = #line) {
        lock.withLock { _messages.append(("INFO", message)) }
    }

    func warning(_ message: String, file: String = #file, line: Int = #line) {
        lock.withLock { _messages.append(("WARN", message)) }
    }

    func error(_ message: String, file: String = #file, line: Int = #line) {
        lock.withLock { _messages.append(("ERROR", message)) }
    }

    func clear() {
        lock.withLock { _messages.removeAll() }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }

    func withLock<T>(_ body: () throws -> T) throws -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

// MARK: - CLI Runner Protocol

protocol CLIRunnerProtocol: Sendable {
    func run(arguments: [String]) async -> CLIResult
}

struct CLIResult: Equatable, Sendable {
    let output: String
    let exitCode: Int32

    static let success = CLIResult(output: "", exitCode: 0)
    static func failure(_ message: String) -> CLIResult {
        CLIResult(output: message, exitCode: 1)
    }
}

// MARK: - Real CLI Runner

final class RealCLIRunner: CLIRunnerProtocol, @unchecked Sendable {
    private let cliPath: String?
    private let logger: GUILoggerProtocol

    init(cliPath: String?, logger: GUILoggerProtocol) {
        self.cliPath = cliPath
        self.logger = logger
    }

    func run(arguments: [String]) async -> CLIResult {
        guard let cliPath = cliPath else {
            logger.error("CLI binary not embedded in app bundle")
            return CLIResult(output: "CLI binary not found. The app was not built correctly - please rebuild with 'swift build -c release' before building the app.", exitCode: 1)
        }

        logger.debug("Running CLI: \(cliPath) \(arguments.joined(separator: " "))")

        guard FileManager.default.fileExists(atPath: cliPath) else {
            logger.error("CLI not found at \(cliPath)")
            return CLIResult(output: "CLI not found at \(cliPath). Please rebuild the app.", exitCode: 1)
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [cliPath, logger] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let error = String(data: errorData, encoding: .utf8) ?? ""

                    let combined = output.isEmpty ? error : output
                    continuation.resume(returning: CLIResult(
                        output: combined.trimmingCharacters(in: .whitespacesAndNewlines),
                        exitCode: process.terminationStatus
                    ))
                } catch {
                    logger.error("Failed to run CLI: \(error.localizedDescription)")
                    continuation.resume(returning: CLIResult(output: error.localizedDescription, exitCode: 1))
                }
            }
        }
    }
}

// MARK: - Mock CLI Runner for Testing

actor MockCLIRunner: CLIRunnerProtocol {
    var responses: [String: CLIResult] = [:]
    var callHistory: [[String]] = []

    func setResponse(for command: String, result: CLIResult) {
        responses[command] = result
    }

    func run(arguments: [String]) async -> CLIResult {
        callHistory.append(arguments)
        let command = arguments.first ?? ""
        return responses[command] ?? .success
    }

    func getCallHistory() -> [[String]] {
        callHistory
    }

    func clear() {
        responses.removeAll()
        callHistory.removeAll()
    }
}

// MARK: - File System Protocol

protocol FileSystemProtocol: Sendable {
    func fileExists(atPath path: String) -> Bool
    func readData(atPath path: String) throws -> Data
    func writeData(_ data: Data, toPath path: String) throws
    func createDirectory(atPath path: String) throws
    func setPermissions(_ permissions: Int, atPath path: String) throws
}

// MARK: - Real File System

final class RealFileSystem: FileSystemProtocol, @unchecked Sendable {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func readData(atPath path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func writeData(_ data: Data, toPath path: String) throws {
        try data.write(to: URL(fileURLWithPath: path))
    }

    func createDirectory(atPath path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func setPermissions(_ permissions: Int, atPath path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
    }
}

// MARK: - Mock File System for Testing

final class MockFileSystem: FileSystemProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _files: [String: Data] = [:]
    private var _directories: Set<String> = []

    func fileExists(atPath path: String) -> Bool {
        lock.withLock {
            _files[path] != nil || _directories.contains(path)
        }
    }

    func readData(atPath path: String) throws -> Data {
        try lock.withLock {
            guard let data = _files[path] else {
                throw NSError(domain: "MockFS", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
            }
            return data
        }
    }

    func writeData(_ data: Data, toPath path: String) throws {
        lock.withLock {
            _files[path] = data
        }
    }

    func createDirectory(atPath path: String) throws {
        lock.withLock {
            _ = _directories.insert(path)
        }
    }

    func setPermissions(_ permissions: Int, atPath path: String) throws {}

    func setFile(_ path: String, content: String) {
        lock.withLock {
            _files[path] = content.data(using: .utf8)!
        }
    }

    func getFile(_ path: String) -> String? {
        lock.withLock {
            _files[path].flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    func clear() {
        lock.withLock {
            _files.removeAll()
            _directories.removeAll()
        }
    }
}

// MARK: - SyncViewModel Dependencies

struct SyncViewModelDependencies: Sendable {
    let configPath: String
    let statePath: String
    let cliPath: String?  // nil if CLI not found (app not built correctly)
    let cliRunner: CLIRunnerProtocol
    let fileSystem: FileSystemProtocol
    let logger: GUILoggerProtocol

    /// Find CLI binary - must be embedded in app bundle or available for development
    /// No fallback to system install to ensure version consistency
    static func findCLIPath() -> String? {
        let fm = FileManager.default

        // 1. Check inside app bundle Resources (production)
        if let bundlePath = Bundle.main.resourcePath {
            let embeddedPath = "\(bundlePath)/ics-calendar-sync"
            if fm.fileExists(atPath: embeddedPath) {
                return embeddedPath
            }
        }

        // 2. Check in app bundle's MacOS directory (alternative location)
        if let execPath = Bundle.main.executablePath {
            let macOSDir = (execPath as NSString).deletingLastPathComponent
            let siblingPath = "\(macOSDir)/ics-calendar-sync"
            if fm.fileExists(atPath: siblingPath) {
                return siblingPath
            }
        }

        // 3. Check alongside the app bundle (for development builds only)
        if let bundlePath = Bundle.main.bundlePath as NSString? {
            let parentDir = bundlePath.deletingLastPathComponent
            // Check .build/debug for SPM builds
            let debugPath = "\(parentDir)/.build/debug/ics-calendar-sync"
            if fm.fileExists(atPath: debugPath) {
                return debugPath
            }
            // Check .build/release for SPM release builds
            let releasePath = "\(parentDir)/.build/release/ics-calendar-sync"
            if fm.fileExists(atPath: releasePath) {
                return releasePath
            }
        }

        // No fallback - CLI must be embedded or available for development
        return nil
    }

    static func createDefault() -> SyncViewModelDependencies {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(home)/.config/ics-calendar-sync/gui-config.json"
        let statePath = "\(home)/.local/share/ics-calendar-sync/state.db"
        let cliPath = findCLIPath()
        let logger = GUILogger.shared

        if let cliPath = cliPath {
            logger.info("Using CLI at: \(cliPath)")
        } else {
            logger.error("CLI binary not found! App may not have been built correctly. Build CLI first with 'swift build -c release'")
        }

        return SyncViewModelDependencies(
            configPath: configPath,
            statePath: statePath,
            cliPath: cliPath,
            cliRunner: RealCLIRunner(cliPath: cliPath, logger: logger),
            fileSystem: RealFileSystem(),
            logger: logger
        )
    }
}

// MARK: - Service Status

enum ServiceStatus: Equatable {
    case notInstalled
    case running
    case stopped

    var description: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .running: return "Running"
        case .stopped: return "Stopped"
        }
    }
}

// MARK: - SyncViewModel

@MainActor
class SyncViewModel: ObservableObject {
    // Published properties for UI
    @Published var status: SyncStatus = .idle
    @Published var lastSyncTime: Date?
    @Published var eventCount: Int = 0
    @Published var isServiceRunning: Bool = false
    @Published var isServiceInstalled: Bool = false
    @Published var lastError: String?

    // Multi-feed configuration
    @Published var feeds: [FeedConfiguration] = []
    @Published var notificationsEnabled: Bool = false
    @Published var defaultCalendar: String = ""
    @Published var selectedFeedID: UUID?

    // Calendar access
    @Published var availableCalendars: [CalendarInfo] = []
    @Published var calendarAccessStatus: EKAuthorizationStatus = .notDetermined
    @Published var hasCalendarAccess: Bool = false
    private let eventStore = EKEventStore()

    // Notification access
    @Published var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    // Dependencies
    private let deps: SyncViewModelDependencies
    private var refreshTimer: Timer?

    // Service constants (nonisolated for use in async closures)
    private nonisolated static let serviceLabel = "com.ics-calendar-sync"
    private nonisolated static var launchAgentPlistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(serviceLabel).plist"
    }
    private nonisolated static var logDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Logs/ics-calendar-sync"
    }

    // Available sync intervals
    let syncIntervals = [5, 15, 30, 60]

    var menuBarIcon: String {
        status.icon
    }

    var hasFeeds: Bool {
        !feeds.isEmpty
    }

    var enabledFeeds: [FeedConfiguration] {
        feeds.filter { $0.isEnabled }
    }

    // MARK: - Initialization

    convenience init() {
        self.init(dependencies: .createDefault())
    }

    init(dependencies: SyncViewModelDependencies, autoLoad: Bool = true) {
        self.deps = dependencies
        deps.logger.info("GUI initialized")

        if autoLoad {
            Task {
                await loadAll()
                startRefreshTimer()
            }
        }
    }

    // MARK: - Refresh Timer

    func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshStatus()
            }
        }
    }

    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Load All Data

    func loadAll() async {
        deps.logger.debug("Loading all data")
        await loadConfig()
        await loadSyncState()
        await checkServiceStatus()
        await loadCalendars()
        await checkNotificationStatus()

        // Auto-install service on first run
        await autoInstallServiceIfNeeded()
    }

    // MARK: - Notification Status

    func checkNotificationStatus() async {
        notificationAuthStatus = await NotificationManager.shared.checkAuthorizationStatus()
        deps.logger.debug("Notification authorization status: \(notificationAuthStatus.rawValue)")
    }

    func requestNotificationPermission() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        notificationAuthStatus = granted ? .authorized : .denied
    }

    // MARK: - Calendar Access

    func loadCalendars() async {
        deps.logger.debug("Loading available calendars from EventKit")

        // Check current authorization status
        if #available(macOS 14.0, *) {
            calendarAccessStatus = EKEventStore.authorizationStatus(for: .event)
        } else {
            calendarAccessStatus = EKEventStore.authorizationStatus(for: .event)
        }

        // Request access if needed
        if calendarAccessStatus == .notDetermined {
            do {
                if #available(macOS 14.0, *) {
                    let granted = try await eventStore.requestFullAccessToEvents()
                    calendarAccessStatus = granted ? .fullAccess : .denied
                } else {
                    let granted = try await eventStore.requestAccess(to: .event)
                    calendarAccessStatus = granted ? .authorized : .denied
                }
            } catch {
                deps.logger.error("Failed to request calendar access: \(error.localizedDescription)")
                return
            }
        }

        // Check if we have access
        if #available(macOS 14.0, *) {
            hasCalendarAccess = calendarAccessStatus == .fullAccess || calendarAccessStatus == .writeOnly
        } else {
            hasCalendarAccess = calendarAccessStatus == .authorized
        }

        guard hasCalendarAccess else {
            deps.logger.warning("Calendar access not granted: \(calendarAccessStatus.rawValue)")
            return
        }

        // Fetch all calendars
        let calendars = eventStore.calendars(for: .event)
        availableCalendars = calendars
            .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
            .map { CalendarInfo(from: $0) }

        deps.logger.info("Loaded \(availableCalendars.count) calendars from EventKit")
    }

    // MARK: - Configuration

    func loadConfig() async {
        deps.logger.debug("Loading configuration from \(deps.configPath)")

        guard deps.fileSystem.fileExists(atPath: deps.configPath) else {
            // Try to migrate from legacy config
            await migrateLegacyConfig()
            return
        }

        do {
            let data = try deps.fileSystem.readData(atPath: deps.configPath)
            let config = try JSONDecoder().decode(GUIConfiguration.self, from: data)

            feeds = config.feeds
            notificationsEnabled = config.notificationsEnabled
            defaultCalendar = config.defaultCalendar

            deps.logger.info("Configuration loaded: \(feeds.count) feeds")
        } catch {
            deps.logger.error("Failed to load config: \(error.localizedDescription)")
        }
    }

    private func migrateLegacyConfig() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let legacyPath = "\(home)/.config/ics-calendar-sync/config.json"

        guard deps.fileSystem.fileExists(atPath: legacyPath) else {
            deps.logger.info("No legacy config found")
            return
        }

        deps.logger.info("Migrating legacy config")

        do {
            let data = try deps.fileSystem.readData(atPath: legacyPath)
            let legacy = try JSONDecoder().decode(LegacyConfiguration.self, from: data)

            if let url = legacy.source?.url, !url.isEmpty {
                let feed = FeedConfiguration(
                    name: legacy.destination?.calendarName ?? "Imported Feed",
                    icsURL: url,
                    calendarName: legacy.destination?.calendarName ?? "Subscribed Events",
                    syncInterval: legacy.daemon?.intervalMinutes ?? 15,
                    deleteOrphans: legacy.sync?.deleteOrphans ?? true,
                    isEnabled: true
                )
                feeds = [feed]
                notificationsEnabled = legacy.notifications?.enabled ?? false

                await saveConfig()
                deps.logger.info("Migrated legacy config to multi-feed format")
            }
        } catch {
            deps.logger.error("Failed to migrate legacy config: \(error.localizedDescription)")
        }
    }

    func saveConfig() async {
        deps.logger.info("Saving configuration")

        let wasServiceRunning = isServiceRunning

        do {
            // Custom encoding to handle the config properly
            var configDict: [String: Any] = [
                "notifications_enabled": notificationsEnabled,
                "global_sync_interval": 15,
                "default_calendar": defaultCalendar
            ]

            let feedsArray = feeds.map { feed -> [String: Any] in
                [
                    "id": feed.id.uuidString,
                    "name": feed.name,
                    "icsURL": feed.icsURL,
                    "calendarName": feed.calendarName,
                    "syncInterval": feed.syncInterval,
                    "deleteOrphans": feed.deleteOrphans,
                    "isEnabled": feed.isEnabled,
                    "notificationsEnabled": feed.notificationsEnabled
                ]
            }
            configDict["feeds"] = feedsArray

            let configDir = (deps.configPath as NSString).deletingLastPathComponent
            try deps.fileSystem.createDirectory(atPath: configDir)

            let jsonData = try JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted, .sortedKeys])
            try deps.fileSystem.writeData(jsonData, toPath: deps.configPath)
            try deps.fileSystem.setPermissions(0o600, atPath: deps.configPath)

            lastError = nil
            deps.logger.info("Configuration saved: \(feeds.count) feeds")

            // Restart daemon if it was running so it picks up new config
            if wasServiceRunning && isServiceInstalled {
                deps.logger.info("Restarting daemon to apply config changes...")
                await stopService()
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                await startService()
            }
        } catch {
            deps.logger.error("Failed to save config: \(error.localizedDescription)")
            lastError = "Failed to save configuration: \(error.localizedDescription)"
        }
    }

    private func writeCliConfigForFeed(_ feed: FeedConfiguration) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configDir = "\(home)/.config/ics-calendar-sync"
        let feedConfigPath = "\(configDir)/feed-\(feed.id.uuidString).json"

        let cliConfig: [String: Any] = [
            "source": ["url": feed.icsURL],
            "destination": ["calendar_name": feed.calendarName],
            "sync": ["delete_orphans": feed.deleteOrphans],
            "daemon": ["interval_minutes": feed.syncInterval],
            "notifications": ["enabled": notificationsEnabled]
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: cliConfig, options: [.prettyPrinted])
            try deps.fileSystem.createDirectory(atPath: configDir)
            try deps.fileSystem.writeData(jsonData, toPath: feedConfigPath)
            try deps.fileSystem.setPermissions(0o600, atPath: feedConfigPath)
            return feedConfigPath
        } catch {
            deps.logger.error("Failed to write CLI config for feed \(feed.name): \(error)")
            return nil
        }
    }

    // MARK: - Feed Management

    func addFeed(_ feed: FeedConfiguration) {
        feeds.append(feed)
        deps.logger.info("Added feed: \(feed.displayName)")
    }

    func updateFeed(_ feed: FeedConfiguration) {
        if let index = feeds.firstIndex(where: { $0.id == feed.id }) {
            feeds[index] = feed
            deps.logger.info("Updated feed: \(feed.displayName)")
        }
    }

    func deleteFeed(_ feed: FeedConfiguration) {
        feeds.removeAll { $0.id == feed.id }
        deps.logger.info("Deleted feed: \(feed.displayName)")
    }

    func deleteFeed(at offsets: IndexSet) {
        let feedNames = offsets.map { feeds[$0].displayName }.joined(separator: ", ")
        feeds.remove(atOffsets: offsets)
        deps.logger.info("Deleted feeds: \(feedNames)")
    }

    func toggleFeed(_ feed: FeedConfiguration) {
        if let index = feeds.firstIndex(where: { $0.id == feed.id }) {
            feeds[index].isEnabled.toggle()
            deps.logger.info("Toggled feed \(feed.displayName): \(feeds[index].isEnabled ? "enabled" : "disabled")")
        }
    }

    // MARK: - Sync State

    func loadSyncState() async {
        deps.logger.debug("Loading sync state from \(deps.statePath)")

        guard deps.fileSystem.fileExists(atPath: deps.statePath) else {
            deps.logger.debug("State database not found")
            eventCount = 0
            lastSyncTime = nil
            return
        }

        do {
            let db = try Connection(deps.statePath, readonly: true)

            let eventsTable = Table("synced_events")
            eventCount = try db.scalar(eventsTable.count)

            let historyTable = Table("sync_history")
            let statusCol = Expression<String>("status")
            let completedCol = Expression<String?>("completed_at")

            let query = historyTable
                .filter(statusCol == "success")
                .order(Expression<Int64>("id").desc)
                .limit(1)

            if let row = try db.pluck(query),
               let completedStr = row[completedCol] {
                lastSyncTime = ISO8601DateFormatter().date(from: completedStr)
            }

            deps.logger.info("State loaded: \(eventCount) events")
        } catch {
            deps.logger.error("Failed to load sync state: \(error.localizedDescription)")
            eventCount = 0
            lastSyncTime = nil
        }
    }

    // MARK: - Service Control (Direct Launchd Management)

    /// Check service status directly via launchctl (no CLI dependency)
    func checkServiceStatus() async {
        deps.logger.debug("Checking service status")

        // Check if plist exists (installed)
        isServiceInstalled = FileManager.default.fileExists(atPath: Self.launchAgentPlistPath)

        // Check if running via launchctl
        isServiceRunning = await checkLaunchctlRunning()

        deps.logger.debug("Service installed: \(isServiceInstalled), running: \(isServiceRunning)")
    }

    /// Get detailed service status
    func getServiceStatus() async -> ServiceStatus {
        await checkServiceStatus()
        if !isServiceInstalled {
            return .notInstalled
        }
        return isServiceRunning ? .running : .stopped
    }

    private func checkLaunchctlRunning() async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["list", Self.serviceLabel]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Install the background service (creates LaunchAgent plist and loads it)
    func installService() async -> Bool {
        deps.logger.info("Installing background service")

        // Check if CLI path exists
        guard let cliPath = deps.cliPath else {
            lastError = "CLI binary not embedded in app. Cannot install service."
            deps.logger.error(lastError!)
            return false
        }

        // Check if CLI file exists
        guard FileManager.default.fileExists(atPath: cliPath) else {
            lastError = "CLI not found at \(cliPath). Cannot install service."
            deps.logger.error(lastError!)
            return false
        }

        // Verify we have at least one feed
        guard feeds.first(where: { $0.isEnabled }) != nil || !feeds.isEmpty else {
            lastError = "No feeds configured. Please add a feed first."
            deps.logger.error(lastError!)
            return false
        }

        // Use the unified GUI config path directly (CLI now understands GUI format)
        let configPath = deps.configPath
        deps.logger.info("Using unified config at \(configPath)")

        // Create log directory
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.logDir) {
            do {
                try fm.createDirectory(atPath: Self.logDir, withIntermediateDirectories: true)
            } catch {
                lastError = "Failed to create log directory: \(error.localizedDescription)"
                deps.logger.error(lastError!)
                return false
            }
        }

        // Create LaunchAgents directory if needed
        let launchAgentsDir = (Self.launchAgentPlistPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: launchAgentsDir) {
            do {
                try fm.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
            } catch {
                lastError = "Failed to create LaunchAgents directory: \(error.localizedDescription)"
                deps.logger.error(lastError!)
                return false
            }
        }

        // Generate plist content with unified config path
        let plistContent = generateLaunchAgentPlist(cliPath: cliPath, configPath: configPath)

        // Write plist file
        do {
            try plistContent.write(toFile: Self.launchAgentPlistPath, atomically: true, encoding: .utf8)
            deps.logger.info("Created plist at \(Self.launchAgentPlistPath)")
        } catch {
            lastError = "Failed to write plist: \(error.localizedDescription)"
            deps.logger.error(lastError!)
            return false
        }

        // Load the service
        let loadSuccess = await runLaunchctl(["load", Self.launchAgentPlistPath])
        if loadSuccess {
            isServiceInstalled = true
            isServiceRunning = true
            lastError = nil
            deps.logger.info("Service installed and started successfully")
            return true
        } else {
            lastError = "Failed to load service with launchctl"
            deps.logger.error(lastError!)
            return false
        }
    }

    /// Uninstall the background service
    func uninstallService() async -> Bool {
        deps.logger.info("Uninstalling background service")

        guard isServiceInstalled else {
            deps.logger.warning("Service not installed")
            return true
        }

        // Unload the service first
        _ = await runLaunchctl(["unload", Self.launchAgentPlistPath])

        // Remove plist file
        do {
            try FileManager.default.removeItem(atPath: Self.launchAgentPlistPath)
            isServiceInstalled = false
            isServiceRunning = false
            lastError = nil
            deps.logger.info("Service uninstalled successfully")
            return true
        } catch {
            lastError = "Failed to remove plist: \(error.localizedDescription)"
            deps.logger.error(lastError!)
            return false
        }
    }

    /// Start the service (enable)
    func startService() async {
        deps.logger.info("Starting service")

        // If not installed, install first
        if !isServiceInstalled {
            let installed = await installService()
            if !installed {
                status = .error(lastError ?? "Failed to install service")
                return
            }
        }

        let success = await runLaunchctl(["load", Self.launchAgentPlistPath])
        if success {
            isServiceRunning = true
            lastError = nil
            deps.logger.info("Service started successfully")
        } else {
            status = .error("Failed to start service")
            lastError = "Failed to start service"
            deps.logger.error("Failed to start service")
        }
    }

    /// Stop the service (disable)
    func stopService() async {
        deps.logger.info("Stopping service")

        guard isServiceInstalled else {
            deps.logger.warning("Service not installed, nothing to stop")
            return
        }

        let success = await runLaunchctl(["unload", Self.launchAgentPlistPath])
        if success {
            isServiceRunning = false
            lastError = nil
            deps.logger.info("Service stopped successfully")
        } else {
            lastError = "Failed to stop service"
            deps.logger.error("Failed to stop service")
        }
    }

    /// Run launchctl command
    private func runLaunchctl(_ arguments: [String]) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Generate the LaunchAgent plist content
    private func generateLaunchAgentPlist(cliPath: String, configPath: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.serviceLabel)</string>

            <key>ProgramArguments</key>
            <array>
                <string>\(cliPath)</string>
                <string>daemon</string>
                <string>--config</string>
                <string>\(configPath)</string>
            </array>

            <key>RunAtLoad</key>
            <true/>

            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>

            <key>StandardOutPath</key>
            <string>\(Self.logDir)/stdout.log</string>

            <key>StandardErrorPath</key>
            <string>\(Self.logDir)/stderr.log</string>

            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
            </dict>

            <key>ProcessType</key>
            <string>Background</string>

            <key>LowPriorityBackgroundIO</key>
            <true/>

            <key>ThrottleInterval</key>
            <integer>60</integer>
        </dict>
        </plist>
        """
    }

    // MARK: - Auto-Install Service

    /// Check if service should be auto-installed on first run
    func autoInstallServiceIfNeeded() async {
        deps.logger.debug("Checking if service auto-install is needed")

        await checkServiceStatus()

        // Only auto-install if:
        // 1. Service is not installed
        // 2. CLI binary is embedded and exists
        guard let cliPath = deps.cliPath else {
            deps.logger.warning("Cannot auto-install service: CLI binary not embedded in app")
            return
        }

        if !isServiceInstalled && FileManager.default.fileExists(atPath: cliPath) {
            deps.logger.info("Auto-installing service on first run")
            let success = await installService()
            if success {
                deps.logger.info("Service auto-installed successfully")
            } else {
                deps.logger.warning("Service auto-install failed: \(lastError ?? "unknown error")")
            }
        }
    }

    // MARK: - Reset Sync State

    /// Reset sync state for all feeds - next sync will treat all events as new
    func resetSyncState() async {
        deps.logger.info("Resetting sync state for all feeds")

        // Delete the state database
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let statePath = "\(home)/.local/share/ics-calendar-sync/state.db"

        do {
            if deps.fileSystem.fileExists(atPath: statePath) {
                try FileManager.default.removeItem(atPath: statePath)
                deps.logger.info("Sync state reset successfully")
            }
            // Reset in-memory state
            eventCount = 0
            lastSyncTime = nil
            lastError = nil
            status = .idle
        } catch {
            deps.logger.error("Failed to reset sync state: \(error)")
            lastError = "Failed to reset sync state: \(error.localizedDescription)"
        }
    }

    // MARK: - Import/Export Configuration

    /// Export current configuration to a file URL
    func exportConfig(to url: URL) async throws {
        deps.logger.info("Exporting configuration to \(url.path)")

        var configDict: [String: Any] = [
            "notifications_enabled": notificationsEnabled,
            "global_sync_interval": 15,
            "default_calendar": defaultCalendar,
            "version": "2.1.0"
        ]

        let feedsArray = feeds.map { feed -> [String: Any] in
            [
                "id": feed.id.uuidString,
                "name": feed.name,
                "icsURL": feed.icsURL,
                "calendarName": feed.calendarName,
                "syncInterval": feed.syncInterval,
                "deleteOrphans": feed.deleteOrphans,
                "isEnabled": feed.isEnabled,
                "notificationsEnabled": feed.notificationsEnabled
            ]
        }
        configDict["feeds"] = feedsArray

        let data = try JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)

        deps.logger.info("Configuration exported successfully")
    }

    /// Import configuration from a file URL (supports both v2.0 GUI format and legacy CLI format)
    func importConfig(from url: URL) async throws {
        deps.logger.info("Importing configuration from \(url.path)")

        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ICSCalendarSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }

        // Check if this is a v2.0 multi-feed config or legacy CLI config
        if let feedsArray = json["feeds"] as? [[String: Any]] {
            // v2.0 multi-feed format
            try await importV2Config(json: json, feedsArray: feedsArray)
        } else if let sourceDict = json["source"] as? [String: Any], let sourceURL = sourceDict["url"] as? String {
            // Legacy CLI format - convert to single feed
            try await importLegacyCLIConfig(json: json, sourceURL: sourceURL)
        } else {
            throw NSError(domain: "ICSCalendarSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unrecognized configuration format"])
        }

        await saveConfig()
        deps.logger.info("Configuration imported successfully")
    }

    private func importV2Config(json: [String: Any], feedsArray: [[String: Any]]) async throws {
        var importedFeeds: [FeedConfiguration] = []

        for feedDict in feedsArray {
            guard let icsURL = feedDict["icsURL"] as? String else { continue }

            let id: UUID
            if let idString = feedDict["id"] as? String, let uuid = UUID(uuidString: idString) {
                id = uuid
            } else {
                id = UUID()
            }

            let feed = FeedConfiguration(
                id: id,
                name: feedDict["name"] as? String ?? "",
                icsURL: icsURL,
                calendarName: feedDict["calendarName"] as? String ?? "Subscribed Events",
                syncInterval: feedDict["syncInterval"] as? Int ?? 15,
                deleteOrphans: feedDict["deleteOrphans"] as? Bool ?? true,
                isEnabled: feedDict["isEnabled"] as? Bool ?? true,
                notificationsEnabled: feedDict["notificationsEnabled"] as? Bool ?? true
            )
            importedFeeds.append(feed)
        }

        feeds = importedFeeds
        notificationsEnabled = json["notifications_enabled"] as? Bool ?? false
        defaultCalendar = json["default_calendar"] as? String ?? ""
    }

    private func importLegacyCLIConfig(json: [String: Any], sourceURL: String) async throws {
        deps.logger.info("Converting legacy CLI config to v2.0 format")

        // Extract settings from legacy format
        let destDict = json["destination"] as? [String: Any]
        let syncDict = json["sync"] as? [String: Any]
        let daemonDict = json["daemon"] as? [String: Any]
        let notifDict = json["notifications"] as? [String: Any]

        let calendarName = destDict?["calendar_name"] as? String ?? "Subscribed Events"
        let deleteOrphans = syncDict?["delete_orphans"] as? Bool ?? true
        let intervalMinutes = daemonDict?["interval_minutes"] as? Int ?? 15
        let notificationsOn = notifDict?["enabled"] as? Bool ?? false

        // Create a single feed from the legacy config
        let feed = FeedConfiguration(
            id: UUID(),
            name: "Imported from CLI",
            icsURL: sourceURL,
            calendarName: calendarName,
            syncInterval: intervalMinutes,
            deleteOrphans: deleteOrphans,
            isEnabled: true,
            notificationsEnabled: notificationsOn
        )

        feeds = [feed]
        notificationsEnabled = notificationsOn
        defaultCalendar = calendarName
    }

    // MARK: - Sync Operations

    func syncNow() async {
        guard hasFeeds else {
            deps.logger.warning("Cannot sync: no feeds configured")
            lastError = "Please add at least one feed"
            return
        }

        deps.logger.info("Starting sync for all enabled feeds")
        status = .syncing
        lastError = nil

        var anyFailed = false
        var lastErrorMsg = ""
        var successfulSyncs: [(feed: FeedConfiguration, events: Int)] = []

        for feed in enabledFeeds {
            deps.logger.info("Syncing feed: \(feed.displayName)")
            let result = await syncFeed(feed)
            if result.exitCode != 0 {
                anyFailed = true
                lastErrorMsg = result.output
                // Send error notification if global AND per-feed notifications enabled
                if notificationsEnabled && feed.notificationsEnabled {
                    await NotificationManager.shared.sendSyncErrorNotification(
                        feedName: feed.displayName,
                        error: result.output
                    )
                }
            } else {
                successfulSyncs.append((feed: feed, events: eventCount))
            }
        }

        if anyFailed {
            status = .error(lastErrorMsg)
            lastError = lastErrorMsg
        } else {
            status = .success
            deps.logger.info("All feeds synced successfully")
            await loadSyncState()

            // Send success notifications if global AND per-feed notifications enabled
            for sync in successfulSyncs {
                if notificationsEnabled && sync.feed.notificationsEnabled {
                    await NotificationManager.shared.sendSyncSuccessNotification(
                        feedName: sync.feed.displayName,
                        eventCount: eventCount
                    )
                }
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if case .success = status {
                status = .idle
            }
        }
    }

    func syncFeed(_ feed: FeedConfiguration) async -> CLIResult {
        // Write CLI config for this feed on-demand
        guard let feedConfigPath = writeCliConfigForFeed(feed) else {
            return CLIResult(output: "Failed to write config for feed", exitCode: 1)
        }

        return await deps.cliRunner.run(arguments: ["sync", "--config", feedConfigPath])
    }

    // MARK: - Refresh Status

    func refreshStatus() async {
        await loadSyncState()
        await checkServiceStatus()
    }

    // MARK: - Formatting Helpers

    var lastSyncDescription: String {
        guard let time = lastSyncTime else {
            return "Never"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: time, relativeTo: Date())
    }

    var statusDescription: String {
        switch status {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing..."
        case .success:
            return "Sync complete"
        case .error(let msg):
            let truncated = msg.count > 50 ? String(msg.prefix(47)) + "..." : msg
            return "Error: \(truncated)"
        }
    }

    // MARK: - Testing Helpers

    #if DEBUG
    func setStatus(_ newStatus: SyncStatus) {
        status = newStatus
    }

    func setServiceRunning(_ running: Bool) {
        isServiceRunning = running
    }
    #endif
}

// Helper init for GUIConfiguration
extension GUIConfiguration {
    init(feeds: [FeedConfiguration], notificationsEnabled: Bool, globalSyncInterval: Int, defaultCalendar: String = "") {
        self.feeds = feeds
        self.notificationsEnabled = notificationsEnabled
        self.globalSyncInterval = globalSyncInterval
        self.defaultCalendar = defaultCalendar
    }
}
