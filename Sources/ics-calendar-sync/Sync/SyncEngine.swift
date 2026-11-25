import Darwin
import Foundation

// MARK: - Sync Result

/// Result of a sync operation
struct SyncResult: Sendable {
    var created: Int = 0
    var updated: Int = 0
    var deleted: Int = 0
    var unchanged: Int = 0
    var errors: [SyncEventError] = []

    var totalProcessed: Int {
        created + updated + deleted + unchanged
    }

    var hasErrors: Bool {
        !errors.isEmpty
    }

    var isSuccess: Bool {
        errors.isEmpty
    }

    struct SyncEventError: Sendable {
        let uid: String
        let operation: String
        let message: String
    }
}

// MARK: - Sync Lock

/// File-based lock to prevent concurrent syncs
final class SyncLock {
    private let lockPath: String
    private var descriptor: Int32 = -1

    init(path: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.lockPath = path ?? "\(home)/.config/ics-calendar-sync/.sync.lock"
    }

    func acquire() throws {
        guard descriptor == -1 else { throw SyncError.syncInProgress }
        try FileManager.default.createDirectoryIfNeeded(atPath: (lockPath as NSString).deletingLastPathComponent)
        let fd = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let reason = errno
            close(fd)
            if reason == EWOULDBLOCK { throw SyncError.syncInProgress }
            throw POSIXError(POSIXErrorCode(rawValue: reason) ?? .EIO)
        }
        descriptor = fd
    }

    func release() {
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
        // Keep the inode so waiters always lock the same file. The kernel unlocks on exit.
    }

}

// MARK: - Sync Engine

protocol SyncCalendar: Actor {
    func requestAccess() async throws
    func hasAccess() async -> Bool
    func destination(for config: Configuration, dryRun: Bool) throws -> String?
    func inventory(in calendarID: String, eventDates: [Date]) throws -> [String: [CalendarItemMatch]]
    func matches(for uid: String, feed: String, calendar: String, state: SyncedEventRecord?,
                 scanned: [CalendarItemMatch], legacy: SyncStateStore.LegacyIdentifiers?) -> EventMatches
    func save(_ source: ICSEvent, to item: CalendarItemMatch?, in calendarID: String,
              mapping: EventMapper.MappingConfig) throws -> CalendarItemMatch
    func remove(_ item: CalendarItemMatch) throws
    func removeDuplicate(_ item: CalendarItemMatch, keeping keeper: CalendarItemMatch) throws
}

/// Orchestrates the delta sync process between ICS source and calendar
actor SyncEngine {
    private let config: Configuration
    private let calendarManager: any SyncCalendar
    private let stateStore: SyncStateStore
    private let icsParser: ICSParser
    private let icsFetcher: ICSFetcher
    private let logger = Logger.shared
    private let syncLock = SyncLock()

    init(config: Configuration, calendarManager: any SyncCalendar = CalendarManager()) throws {
        self.config = config
        self.calendarManager = calendarManager
        self.stateStore = SyncStateStore(config: config)
        self.icsParser = ICSParser()
        self.icsFetcher = ICSFetcher()
    }

    // MARK: - Initialization

    /// Initialize the sync engine (request permissions, setup state)
    func initialize() async throws {
        // Request calendar access
        try await calendarManager.requestAccess()

        // Initialize state store
        try await stateStore.initialize()
    }

    /// Gracefully shutdown the sync engine
    func shutdown() async {
        logger.debug("Shutting down sync engine")
        await stateStore.close()
    }

    // MARK: - Main Sync

    /// Perform a full sync operation
    func sync(dryRun: Bool = false, fullSync: Bool = false) async throws -> SyncResult {
        var result = SyncResult()

        // Acquire sync lock to prevent concurrent syncs
        try syncLock.acquire()
        defer { syncLock.release() }

        // Verify calendar access is still valid
        guard await calendarManager.hasAccess() else {
            throw SyncError.calendarAccessRevoked
        }

        // Record sync start
        let syncId = dryRun ? nil : try await stateStore.recordSyncStart()

        do {
            // Step 1: Fetch and parse ICS
            logger.info("Fetching ICS from \(config.source.url)")
            guard let url = URL(string: config.source.url) else {
                throw ICSError.invalidURL(config.source.url)
            }

            let fetchConfig = config.getFetchConfig()
            let icsContent = try await icsFetcher.fetch(from: url, config: fetchConfig)

            let icsEvents = try await icsParser.parse(icsContent)
            logger.info("Parsed \(icsEvents.count) events from ICS")

            result = try await reconcile(icsEvents, dryRun: dryRun, fullSync: fullSync)

            // Step 7: Record sync completion
            let status: SyncHistoryRecord.SyncStatus = result.errors.isEmpty ? .success : .partial
            if let syncId {
                try await stateStore.recordSyncComplete(
                    id: syncId,
                    status: status,
                    created: result.created,
                    updated: result.updated,
                    deleted: result.deleted,
                    unchanged: result.unchanged,
                    error: result.errors.first?.message
                )
            }

            logger.info("Sync complete: \(result.created) created, \(result.updated) updated, \(result.deleted) deleted, \(result.unchanged) unchanged")

            if !result.errors.isEmpty {
                logger.warning("\(result.errors.count) errors occurred during sync")
            }

            return result

        } catch {
            // Record sync failure
            if let syncId {
                try? await stateStore.recordSyncComplete(
                    id: syncId,
                    status: .failed,
                    created: result.created,
                    updated: result.updated,
                    deleted: result.deleted,
                    unchanged: result.unchanged,
                    error: error.localizedDescription
                )
            }
            throw error
        }
    }

    // MARK: - Event Processing

    func reconcile(_ icsEvents: [ICSEvent], dryRun: Bool = false, fullSync: Bool = false) async throws -> SyncResult {
        var result = SyncResult()
        // Step 2: Filter events by date window if configured
        let windowFilteredEvents = filterEventsByWindow(icsEvents)
        if windowFilteredEvents.count != icsEvents.count {
            logger.info("Filtered to \(windowFilteredEvents.count) events within date window")
        }

        let filteredEvents = Self.masters(in: windowFilteredEvents)

        // Step 3: Get current sync state
        let currentState = try await stateStore.getAllSyncedEvents()
        let incomingUIDs = Set(filteredEvents.map(\.uid))
        // An override or an out-of-window series master is still present in the source.
        let seriesUIDs = icsEvents.filter { $0.isRecurrenceOverride || $0.recurrenceRule != nil }.map(\.uid)
        let orphans = Set(currentState.keys).subtracting(incomingUIDs).subtracting(seriesUIDs)
        let allowDeletes = config.sync.deleteOrphans && !fullSync && Self.allowDeletions(
            incoming: incomingUIDs.count, tracked: currentState.count, orphans: orphans.count)
        if config.sync.deleteOrphans && !allowDeletes && !orphans.isEmpty {
            logger.warning("Retaining orphans due to full sync or empty/mass-deletion protection")
        }

        guard let calendar = try await calendarManager.destination(for: config, dryRun: dryRun) else {
            result.created = filteredEvents.count
            return result
        }
        let inventory = try await calendarManager.inventory(in: calendar, eventDates: filteredEvents.map(\.startDate))
        let mapping = config.getMappingConfig()
        let feed = config.feedState.id
        let legacy = try await stateStore.legacyIdentifiers()

        // Plan physical deletions before removing anything so duplicate cleanup shares the mass-deletion guard.
        var removals: [(keeper: CalendarItemMatch, copies: [CalendarItemMatch], orphan: Bool)] = []
        for event in filteredEvents {
            do {
                let record = currentState[event.uid]
                let matches = await calendarManager.matches(for: event.uid, feed: feed, calendar: calendar,
                    state: record, scanned: inventory[event.uid] ?? [], legacy: legacy[event.uid])
                let keeper = try await apply(event, matches: matches, record: record, calendar: calendar,
                                             mapping: mapping, fullSync: fullSync, dryRun: dryRun, result: &result)
                if allowDeletes, let keeper, !matches.duplicates.isEmpty {
                    removals.append((keeper, matches.duplicates, false))
                }
            } catch {
                logger.error("Failed to sync \(event.uid): \(error.localizedDescription)")
                result.errors.append(.init(uid: event.uid, operation: "sync", message: error.localizedDescription))
            }
        }

        guard allowDeletes && result.errors.isEmpty else { return result }
        for uid in orphans {
            let matches = await calendarManager.matches(for: uid, feed: feed, calendar: calendar,
                state: currentState[uid], scanned: inventory[uid] ?? [], legacy: nil)
            if let keeper = matches.keeper {
                removals.append((keeper, matches.duplicates, true))
            } else {
                let message = "Retaining state for unresolved orphan \(uid)"
                logger.warning(message)
                result.errors.append(.init(uid: uid, operation: "delete", message: message))
            }
        }

        let copies = removals.reduce(0) { $0 + $1.copies.count }
        guard Self.allowDeletions(incoming: incomingUIDs.count, tracked: Set(currentState.keys).union(incomingUIDs).count + copies,
                                  orphans: orphans.count + copies) else {
            logger.warning("Retaining calendar items because the combined deletion count exceeds the safety threshold")
            return result
        }
        for removal in removals {
            let uid = removal.keeper.marker.uid
            do {
                for copy in removal.copies {
                    if !dryRun { try await calendarManager.removeDuplicate(copy, keeping: removal.keeper) }
                    result.deleted += 1
                }
                if removal.orphan {
                    if !dryRun {
                        try await calendarManager.remove(removal.keeper)
                        try await stateStore.deleteEvent(uid: uid)
                    }
                    result.deleted += 1
                }
            } catch {
                logger.warning("Failed to remove calendar item for \(uid): \(error.localizedDescription)")
                result.errors.append(.init(uid: uid, operation: "delete", message: error.localizedDescription))
            }
        }

        return result
    }

    static func masters(in events: [ICSEvent]) -> [ICSEvent] {
        var byUID = [String: ICSEvent]()
        for event in events where !event.isRecurrenceOverride {
            if let previous = byUID[event.uid], previous.sequence > event.sequence { continue }
            byUID[event.uid] = event
        }
        return Array(byUID.values)
    }

    static func allowDeletions(incoming: Int, tracked: Int, orphans: Int) -> Bool {
        guard incoming > 0 else { return false }
        if tracked > 5 && orphans == tracked { return false }
        if tracked > 10 && orphans > Int(Double(tracked) * 0.9) { return false }
        return true
    }

    private func apply(_ event: ICSEvent, matches: EventMatches, record: SyncedEventRecord?,
                       calendar: String, mapping: EventMapper.MappingConfig, fullSync: Bool,
                       dryRun: Bool, result: inout SyncResult) async throws -> CalendarItemMatch? {
        guard !matches.ambiguous else {
            throw SyncError.configurationError("Ambiguous calendar items for \(event.uid). Review in Calendar.")
        }
        let hash = ContentHash.calculate(for: event)
        if let keeper = matches.keeper {
            if !fullSync, let record, hash == record.contentHash, event.sequence <= record.sequence {
                let external = keeper.externalID ?? ""
                if !dryRun && (record.calendarItemId != external || record.eventIdentifier != keeper.eventID) {
                    try await stateStore.updateCalendarItemId(uid: event.uid, calendarItemId: external,
                                                             eventIdentifier: keeper.eventID)
                }
                result.unchanged += 1
                return keeper
            }
        } else {
            if !matches.legacy.isEmpty {
                throw SyncError.configurationError("Legacy UID \(event.uid) needs ownership review. Run migrate --dry-run.")
            }
            guard record == nil else {
                throw CalendarError.eventNotFound(event.uid)
            }
        }

        var keeper = matches.keeper
        if !dryRun {
            let saved = try await calendarManager.save(event, to: keeper, in: calendar, mapping: mapping)
            try await stateStore.upsertEvent(uid: event.uid, calendarItemId: saved.externalID ?? "",
                eventIdentifier: saved.eventID, contentHash: hash, sequence: event.sequence,
                lastModified: event.lastModified, icsData: event.rawData)
            keeper = saved
        }
        if matches.keeper == nil { result.created += 1 } else { result.updated += 1 }
        return keeper
    }

    // MARK: - Date Window Filtering

    private func filterEventsByWindow(_ events: [ICSEvent]) -> [ICSEvent] {
        let now = Date()

        var startWindow = Date.distantPast
        var endWindow = Date.distantFuture

        if let daysPast = config.sync.windowDaysPast {
            startWindow = now.addingDays(-daysPast)
        }

        if let daysFuture = config.sync.windowDaysFuture {
            endWindow = now.addingDays(daysFuture)
        }

        return events.filter { event in
            // Include if event overlaps with window
            event.endDate >= startWindow && event.startDate <= endWindow
        }
    }

    // MARK: - Status

    /// Get current sync status
    func getStatus() async throws -> SyncStatus {
        let eventCount = try await stateStore.getEventCount()
        let lastSync = try await stateStore.getLastSuccessfulSync()
        let history = try await stateStore.getRecentHistory(limit: 5)

        return SyncStatus(
            eventCount: eventCount,
            lastSuccessfulSync: lastSync,
            recentHistory: history
        )
    }

    struct SyncStatus: Sendable {
        let eventCount: Int
        let lastSuccessfulSync: Date?
        let recentHistory: [SyncHistoryRecord]
    }

    /// Reset sync state
    func resetState() async throws {
        try await stateStore.reset()
        logger.info("Sync state has been reset")
    }
}

// MARK: - Convenience Extensions

extension SyncEngine {
    /// Create a sync engine from configuration file
    static func fromConfigFile(path: String) async throws -> SyncEngine {
        let configManager = ConfigurationManager.shared
        let config = try await configManager.load(from: path)
        return try SyncEngine(config: config)
    }
}
