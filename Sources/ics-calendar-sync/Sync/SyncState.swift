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

    // Table definitions
    private let syncedEvents = Table("synced_events")
    private let syncHistory = Table("sync_history")
    private let syncMetadata = Table("sync_metadata")

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

    init(path: String) {
        self.dbPath = path.expandingTildeInPath
    }

    /// Open database and create tables if needed
    func initialize() throws {
        // Ensure directory exists
        let dirPath = (dbPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectoryIfNeeded(atPath: dirPath)

        // Open database
        db = try Connection(dbPath)

        // Enable WAL mode for better concurrency
        try db?.execute("PRAGMA journal_mode = WAL")

        // Create tables
        try createTables()

        logger.debug("Initialized state database at \(dbPath)")
    }

    /// Create database tables
    private func createTables() throws {
        guard let db = db else { throw SyncError.stateCorrupted }

        // Create synced_events table
        try db.run(syncedEvents.create(ifNotExists: true) { t in
            t.column(sourceUID, primaryKey: true)
            t.column(calendarItemId)
            t.column(eventIdentifier)
            t.column(contentHash)
            t.column(sequence, defaultValue: 0)
            t.column(lastModified)
            t.column(syncedAt)
            t.column(icsData)
        })

        // Create sync_history table
        try db.run(syncHistory.create(ifNotExists: true) { t in
            t.column(historyId, primaryKey: .autoincrement)
            t.column(startedAt)
            t.column(completedAt)
            t.column(status)
            t.column(eventsCreated, defaultValue: 0)
            t.column(eventsUpdated, defaultValue: 0)
            t.column(eventsDeleted, defaultValue: 0)
            t.column(eventsUnchanged, defaultValue: 0)
            t.column(errorMessage)
        })

        // Create sync_metadata table
        try db.run(syncMetadata.create(ifNotExists: true) { t in
            t.column(metaKey, primaryKey: true)
            t.column(metaValue)
            t.column(metaUpdatedAt)
        })

        // Create indexes
        try db.run(syncedEvents.createIndex(calendarItemId, ifNotExists: true))
        try db.run(syncHistory.createIndex(startedAt, ifNotExists: true))
    }

    // MARK: - Event Operations

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

        try db.run(syncedEvents.upsert(
            sourceUID <- uid,
            calendarItemId <- itemId,
            eventIdentifier <- eventId,
            contentHash <- hash,
            sequence <- seq,
            lastModified <- modifiedStr,
            syncedAt <- now,
            icsData <- data,
            onConflictOf: sourceUID
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

        return try db.run(syncHistory.insert(
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

        try db.run(syncMetadata.upsert(
            metaKey <- key,
            metaValue <- value,
            metaUpdatedAt <- formatDate(Date()),
            onConflictOf: metaKey
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

        try db.run(syncedEvents.delete())
        try db.run(syncHistory.delete())
        try db.run(syncMetadata.delete())
        try vacuum()

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

// MARK: - SQLite Upsert Extension

extension Table {
    /// Upsert (insert or update on conflict)
    func upsert(_ values: Setter..., onConflictOf column: SQLite.Expression<String>) -> Insert {
        return insert(or: .replace, values)
    }
}
