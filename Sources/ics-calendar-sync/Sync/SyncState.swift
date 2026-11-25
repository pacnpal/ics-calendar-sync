import FeedState
import Foundation
import SQLite

// MARK: - Synced Event Record

/// Represents a synced event record in the state database
struct SyncedEventRecord: Sendable {
    let sourceUID: String
    let calendarItemId: String
    let eventIdentifier: String?
    let contentHash: String
    let sequence: Int
    let lastModified: Date?
    let syncedAt: Date
    let icsData: String
}

// MARK: - Sync History Record

/// Represents a sync operation in history
struct SyncHistoryRecord: Sendable {
    let id: Int64
    let startedAt: Date
    let completedAt: Date?
    let status: SyncStatus
    let eventsCreated: Int
    let eventsUpdated: Int
    let eventsDeleted: Int
    let eventsUnchanged: Int
    let errorMessage: String?

    enum SyncStatus: String, Sendable {
        case success
        case partial
        case failed
    }
}

// MARK: - Sync State Store

/// Manages persistent sync state using SQLite
actor SyncStateStore {
    private let logger = Logger.shared
    private var db: Connection?
    private let dbPath: String

    private let feed: FeedState
    private var syncedEvents: Table { feed.events }
    private var syncHistory: Table { feed.history }
    private var syncMetadata: Table { feed.metadata }

    // Column definitions for synced_events
    private let sourceUID = SQLite.Expression<String>("source_uid")
    private let calendarItemId = SQLite.Expression<String>("calendar_item_id")
    private let eventIdentifier = SQLite.Expression<String?>("event_identifier")
    private let contentHash = SQLite.Expression<String>("content_hash")
    private let sequence = SQLite.Expression<Int>("sequence")
    private let lastModified = SQLite.Expression<String?>("last_modified")
    private let syncedAt = SQLite.Expression<String>("synced_at")
    private let icsData = SQLite.Expression<String>("ics_data")

    // Column definitions for sync_history
    private let historyId = SQLite.Expression<Int64>("id")
    private let startedAt = SQLite.Expression<String>("started_at")
    private let completedAt = SQLite.Expression<String?>("completed_at")
    private let status = SQLite.Expression<String>("status")
    private let eventsCreated = SQLite.Expression<Int>("events_created")
    private let eventsUpdated = SQLite.Expression<Int>("events_updated")
    private let eventsDeleted = SQLite.Expression<Int>("events_deleted")
    private let eventsUnchanged = SQLite.Expression<Int>("events_unchanged")
    private let errorMessage = SQLite.Expression<String?>("error_message")

    // Column definitions for sync_metadata
    private let metaKey = SQLite.Expression<String>("key")
    private let metaValue = SQLite.Expression<String>("value")
    private let metaUpdatedAt = SQLite.Expression<String>("updated_at")

    // MARK: - Initialization

    init(config: Configuration) {
        self.feed = config.feedState
        self.dbPath = config.state.path.expandingTildeInPath
    }

    /// Open database and create tables if needed
    func initialize() throws {
        // Ensure directory exists
        let dirPath = (dbPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectoryIfNeeded(atPath: dirPath)

        // Open database
        let connection = try Connection(dbPath)
        connection.busyTimeout = 5
        try connection.execute("PRAGMA journal_mode = WAL")
        try FeedState.initialize(connection)
        db = connection
    }

    // MARK: - Event Operations

    struct LegacyIdentifiers {
        let externalID: String
        let eventID: String?
    }

    /// Read-only hints. A v2.1 mapping can identify a candidate for review, never its owner.
    func legacyIdentifiers() throws -> [String: LegacyIdentifiers] {
        guard let db else { throw SyncError.stateCorrupted }
        guard try db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='synced_events'") as? Int64 == 1 else { return [:] }
        var result = [String: LegacyIdentifiers]()
        for row in try db.prepare(Table("synced_events").select(sourceUID, calendarItemId, eventIdentifier)) {
            result[row[sourceUID]] = LegacyIdentifiers(externalID: row[calendarItemId], eventID: row[eventIdentifier])
        }
        return result
    }

    /// Get all synced events
    func getAllSyncedEvents() throws -> [String: SyncedEventRecord] {
        guard let db = db else { throw SyncError.stateCorrupted }

        var records: [String: SyncedEventRecord] = [:]

        for row in try db.prepare(syncedEvents) {
            let record = SyncedEventRecord(
                sourceUID: row[sourceUID],
                calendarItemId: row[calendarItemId],
                eventIdentifier: row[eventIdentifier],
                contentHash: row[contentHash],
                sequence: row[sequence],
                lastModified: row[lastModified].flatMap { parseDate($0) },
                syncedAt: parseDate(row[syncedAt]) ?? Date(),
                icsData: row[icsData]
            )
            records[record.sourceUID] = record
        }

        return records
    }

    /// Get synced event by UID
    func getSyncedEvent(uid: String) throws -> SyncedEventRecord? {
        guard let db = db else { throw SyncError.stateCorrupted }

        let query = syncedEvents.filter(sourceUID == uid)

        guard let row = try db.pluck(query) else { return nil }

        return SyncedEventRecord(
            sourceUID: row[sourceUID],
            calendarItemId: row[calendarItemId],
            eventIdentifier: row[eventIdentifier],
            contentHash: row[contentHash],
            sequence: row[sequence],
            lastModified: row[lastModified].flatMap { parseDate($0) },
            syncedAt: parseDate(row[syncedAt]) ?? Date(),
            icsData: row[icsData]
        )
    }

    /// Insert or update synced event
    func upsertEvent(
        uid: String,
        calendarItemId itemId: String,
        eventIdentifier eventId: String?,
        contentHash hash: String,
        sequence seq: Int,
        lastModified modified: Date? = nil,
        icsData data: String
    ) throws {
        guard let db = db else { throw SyncError.stateCorrupted }

        let now = formatDate(Date())
        let modifiedStr = modified.map { formatDate($0) }

        try db.run(FeedState.eventTable.insert(or: .replace,
            FeedState.owner <- feed.id,
            sourceUID <- uid,
            calendarItemId <- itemId,
            eventIdentifier <- eventId,
            contentHash <- hash,
            sequence <- seq,
            lastModified <- modifiedStr,
            syncedAt <- now,
            icsData <- data
        ))
    }

    /// Update event content hash and sequence
    func updateEvent(uid: String, contentHash hash: String, sequence seq: Int) throws {
        guard let db = db else { throw SyncError.stateCorrupted }

        let event = syncedEvents.filter(sourceUID == uid)
        try db.run(event.update(
            contentHash <- hash,
            sequence <- seq,
            syncedAt <- formatDate(Date())
        ))
    }

    /// Update calendar item identifier (after event recreation)
    func updateCalendarItemId(uid: String, calendarItemId itemId: String, eventIdentifier eventId: String?) throws {
        guard let db = db else { throw SyncError.stateCorrupted }

        let event = syncedEvents.filter(sourceUID == uid)
        try db.run(event.update(
            calendarItemId <- itemId,
            eventIdentifier <- eventId,
            syncedAt <- formatDate(Date())
        ))
    }

    /// Delete synced event
    func deleteEvent(uid: String) throws {
        guard let db = db else { throw SyncError.stateCorrupted }

        let event = syncedEvents.filter(sourceUID == uid)
        try db.run(event.delete())
    }

    /// Delete all synced events
    func deleteAllEvents() throws {
        guard let db = db else { throw SyncError.stateCorrupted }
        try db.run(syncedEvents.delete())
    }

    /// Get count of synced events
    func getEventCount() throws -> Int {
        guard let db = db else { throw SyncError.stateCorrupted }
        return try db.scalar(syncedEvents.count)
    }

    // MARK: - Sync History Operations

    /// Record start of sync operation
    func recordSyncStart() throws -> Int64 {
        guard let db = db else { throw SyncError.stateCorrupted }

        return try db.run(FeedState.historyTable.insert(
            FeedState.owner <- feed.id,
            startedAt <- formatDate(Date()),
            status <- SyncHistoryRecord.SyncStatus.failed.rawValue,
            eventsCreated <- 0,
            eventsUpdated <- 0,
            eventsDeleted <- 0,
            eventsUnchanged <- 0
        ))
    }

    /// Update sync operation with results
    func recordSyncComplete(
        id: Int64,
        status syncStatus: SyncHistoryRecord.SyncStatus,
        created: Int,
        updated: Int,
        deleted: Int,
        unchanged: Int,
        error: String? = nil
    ) throws {
        guard let db = db else { throw SyncError.stateCorrupted }

        let record = syncHistory.filter(historyId == id)
        try db.run(record.update(
            completedAt <- formatDate(Date()),
            status <- syncStatus.rawValue,
            eventsCreated <- created,
            eventsUpdated <- updated,
            eventsDeleted <- deleted,
            eventsUnchanged <- unchanged,
            errorMessage <- error
        ))
    }

    /// Get recent sync history
    func getRecentHistory(limit: Int = 10) throws -> [SyncHistoryRecord] {
        guard let db = db else { throw SyncError.stateCorrupted }

        let query = syncHistory
            .order(historyId.desc)
            .limit(limit)

        var records: [SyncHistoryRecord] = []

        for row in try db.prepare(query) {
            let record = SyncHistoryRecord(
                id: row[historyId],
                startedAt: parseDate(row[startedAt]) ?? Date(),
                completedAt: row[completedAt].flatMap { parseDate($0) },
                status: SyncHistoryRecord.SyncStatus(rawValue: row[status]) ?? .failed,
                eventsCreated: row[eventsCreated],
                eventsUpdated: row[eventsUpdated],
                eventsDeleted: row[eventsDeleted],
                eventsUnchanged: row[eventsUnchanged],
                errorMessage: row[errorMessage]
            )
            records.append(record)
        }

        return records
    }

    /// Get last successful sync time
    func getLastSuccessfulSync() throws -> Date? {
        guard let db = db else { throw SyncError.stateCorrupted }

        let query = syncHistory
            .filter(status == SyncHistoryRecord.SyncStatus.success.rawValue)
            .order(historyId.desc)
            .limit(1)

        guard let row = try db.pluck(query),
              let completedStr = row[completedAt] else {
            return nil
        }

        return parseDate(completedStr)
    }

    // MARK: - Metadata Operations

    /// Set metadata value
    func setMetadata(key: String, value: String) throws {
        guard let db = db else { throw SyncError.stateCorrupted }

        try db.run(FeedState.metadataTable.insert(or: .replace,
            FeedState.owner <- feed.id,
            metaKey <- key,
            metaValue <- value,
            metaUpdatedAt <- formatDate(Date())
        ))
    }

    /// Get metadata value
    func getMetadata(key: String) throws -> String? {
        guard let db = db else { throw SyncError.stateCorrupted }

        let query = syncMetadata.filter(metaKey == key)
        guard let row = try db.pluck(query) else { return nil }
        return row[metaValue]
    }

    // MARK: - Maintenance

    /// Vacuum database to reclaim space
    func vacuum() throws {
        guard let db = db else { throw SyncError.stateCorrupted }
        try db.vacuum()
    }

    /// Check database integrity
    func checkIntegrity() throws -> Bool {
        guard let db = db else { throw SyncError.stateCorrupted }

        let result = try db.scalar("PRAGMA integrity_check") as? String
        return result == "ok"
    }

    /// Reset all state
    func reset() throws {
        guard let db = db else { throw SyncError.stateCorrupted }

        try db.transaction { try feed.reset(in: db) }

        logger.info("State database reset")
    }

    /// Close database connection gracefully
    func close() {
        if db != nil {
            logger.debug("Closing state database")
            db = nil
        }
    }

    // MARK: - Helper Methods

    private func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func parseDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
