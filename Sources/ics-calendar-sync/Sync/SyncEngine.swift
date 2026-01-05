import Foundation
import EventKit

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

// MARK: - Sync Engine

/// Orchestrates the delta sync process between ICS source and calendar
actor SyncEngine {
    private let config: Configuration
    private let calendarManager: CalendarManager
    private let stateStore: SyncStateStore
    private let icsParser: ICSParser
    private let icsFetcher: ICSFetcher
    private let logger = Logger.shared

    init(config: Configuration) throws {
        self.config = config
        self.calendarManager = CalendarManager()
        self.stateStore = SyncStateStore(path: config.state.path)
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

    // MARK: - Main Sync

    /// Perform a full sync operation
    func sync(dryRun: Bool = false, fullSync: Bool = false) async throws -> SyncResult {
        var result = SyncResult()

        // Record sync start
        let syncId = try await stateStore.recordSyncStart()

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

            // Step 2: Filter events by date window if configured
            let windowFilteredEvents = filterEventsByWindow(icsEvents)
            if windowFilteredEvents.count != icsEvents.count {
                logger.info("Filtered to \(windowFilteredEvents.count) events within date window")
            }

            // Step 2b: Deduplicate events with same UID (keep last occurrence - highest sequence wins)
            // This prevents duplicates if ICS feed contains same event multiple times
            var uniqueEvents: [String: ICSEvent] = [:]
            for event in windowFilteredEvents {
                if let existing = uniqueEvents[event.uid] {
                    // Keep the one with higher sequence number, or the later one if equal
                    if event.sequence >= existing.sequence {
                        uniqueEvents[event.uid] = event
                    }
                } else {
                    uniqueEvents[event.uid] = event
                }
            }
            let filteredEvents = Array(uniqueEvents.values)
            if filteredEvents.count != windowFilteredEvents.count {
                logger.info("Deduplicated to \(filteredEvents.count) unique events")
            }

            // Step 3: Get current sync state
            let currentState: [String: SyncedEventRecord]
            if fullSync {
                currentState = [:]
                logger.info("Full sync requested - ignoring existing state")
            } else {
                currentState = try await stateStore.getAllSyncedEvents()
                logger.debug("Found \(currentState.count) events in sync state")
            }

            let currentUIDs = Set(currentState.keys)
            let incomingUIDs = Set(filteredEvents.map { $0.uid })

            // Step 4: Find or create target calendar
            let calendar = try await getOrCreateCalendar()
            logger.info("Using calendar: \(calendar.title)")

            // Step 5: Process events
            let mappingConfig = config.getMappingConfig()

            // Process incoming events (create or update)
            for icsEvent in filteredEvents {
                do {
                    if let existingState = currentState[icsEvent.uid] {
                        // Event exists - check if changed
                        let processResult = try await processExistingEvent(
                            icsEvent: icsEvent,
                            existingState: existingState,
                            calendar: calendar,
                            mappingConfig: mappingConfig,
                            dryRun: dryRun
                        )

                        switch processResult {
                        case .updated:
                            result.updated += 1
                        case .unchanged:
                            result.unchanged += 1
                        case .recreated:
                            result.updated += 1
                        }
                    } else {
                        // New event - create
                        try await processNewEvent(
                            icsEvent: icsEvent,
                            calendar: calendar,
                            mappingConfig: mappingConfig,
                            dryRun: dryRun
                        )
                        result.created += 1
                    }
                } catch {
                    logger.error("Failed to process event \(icsEvent.uid): \(error)")
                    result.errors.append(SyncResult.SyncEventError(
                        uid: icsEvent.uid,
                        operation: currentState[icsEvent.uid] != nil ? "update" : "create",
                        message: error.localizedDescription
                    ))
                }
            }

            // Step 6: Handle deletions (orphans)
            if config.sync.deleteOrphans {
                let orphanUIDs = currentUIDs.subtracting(incomingUIDs)

                for uid in orphanUIDs {
                    do {
                        try await processDeletedEvent(uid: uid, currentState: currentState, dryRun: dryRun)
                        result.deleted += 1
                    } catch {
                        logger.error("Failed to delete orphan \(uid): \(error)")
                        result.errors.append(SyncResult.SyncEventError(
                            uid: uid,
                            operation: "delete",
                            message: error.localizedDescription
                        ))
                    }
                }
            }

            // Step 7: Record sync completion
            let status: SyncHistoryRecord.SyncStatus = result.errors.isEmpty ? .success : .partial
            try await stateStore.recordSyncComplete(
                id: syncId,
                status: status,
                created: result.created,
                updated: result.updated,
                deleted: result.deleted,
                unchanged: result.unchanged,
                error: result.errors.first?.message
            )

            logger.info("Sync complete: \(result.created) created, \(result.updated) updated, \(result.deleted) deleted, \(result.unchanged) unchanged")

            if !result.errors.isEmpty {
                logger.warning("\(result.errors.count) errors occurred during sync")
            }

            return result

        } catch {
            // Record sync failure
            try? await stateStore.recordSyncComplete(
                id: syncId,
                status: .failed,
                created: result.created,
                updated: result.updated,
                deleted: result.deleted,
                unchanged: result.unchanged,
                error: error.localizedDescription
            )
            throw error
        }
    }

    // MARK: - Event Processing

    private enum ProcessResult {
        case updated
        case unchanged
        case recreated
    }

    private func processExistingEvent(
        icsEvent: ICSEvent,
        existingState: SyncedEventRecord,
        calendar: EKCalendar,
        mappingConfig: EventMapper.MappingConfig,
        dryRun: Bool
    ) async throws -> ProcessResult {
        let newHash = ContentHash.calculate(for: icsEvent)

        // Check if content changed
        let contentChanged = newHash != existingState.contentHash
        let sequenceChanged = icsEvent.sequence > existingState.sequence

        // Find existing event in calendar first (we need it to check for UID marker)
        // Try external ID first (most stable), then fall back to event identifier
        var ekEvent: EKEvent? = nil

        if !existingState.calendarItemId.isEmpty {
            ekEvent = await calendarManager.findEvent(byExternalId: existingState.calendarItemId)
        }

        // Fallback to event identifier if external ID didn't work
        if ekEvent == nil, let eventId = existingState.eventIdentifier, !eventId.isEmpty {
            ekEvent = await calendarManager.findEvent(byEventId: eventId)
        }

        // Bulletproof fallback: search by ICS UID embedded in event notes
        // This searches the ENTIRE calendar - most reliable as UID is stored in event itself
        if ekEvent == nil {
            logger.debug("Searching for event by embedded UID: \(icsEvent.uid)")
            ekEvent = await calendarManager.findEvent(byICSUID: icsEvent.uid, in: calendar)
        }

        // Last resort: search by matching event properties (title, dates)
        // This handles legacy events that don't have the UID marker
        if ekEvent == nil {
            logger.debug("Searching for event by properties: \(icsEvent.displayTitle)")
            ekEvent = await calendarManager.findEvent(matching: icsEvent, in: calendar, config: mappingConfig)
        }

        // If found by any fallback method, update the stored identifiers for future lookups
        if let foundEvent = ekEvent {
            if let externalId = foundEvent.calendarItemExternalIdentifier,
               !externalId.isEmpty,
               externalId != existingState.calendarItemId {
                try? await stateStore.updateCalendarItemId(
                    uid: icsEvent.uid,
                    calendarItemId: externalId,
                    eventIdentifier: foundEvent.eventIdentifier
                )
            }
        }

        // Check if event needs UID marker migration
        let needsUIDMarker = ekEvent != nil && !EventMapper.containsUIDMarker(ekEvent?.notes)

        // If content unchanged AND event already has UID marker, skip update
        // Note: If ekEvent is nil but content unchanged, we still skip to avoid creating duplicates
        // The event might exist but our lookup failed to find it
        if !contentChanged && !sequenceChanged && !needsUIDMarker {
            if ekEvent == nil {
                logger.debug("Event not found but content unchanged, skipping to avoid duplicate: \(icsEvent.uid)")
            }
            return .unchanged
        }

        // Log what we're doing
        if needsUIDMarker && !contentChanged && !sequenceChanged {
            logger.info("Migrating (adding UID marker): \(icsEvent.displayTitle)")
        } else {
            logger.info("Updating: \(icsEvent.displayTitle)")
        }

        if dryRun {
            return .updated
        }

        if let ekEvent = ekEvent {
            // Update existing event (this also adds UID marker via EventMapper.apply)
            try await calendarManager.updateEvent(ekEvent, from: icsEvent, config: mappingConfig)

            try await stateStore.updateEvent(
                uid: icsEvent.uid,
                contentHash: newHash,
                sequence: icsEvent.sequence
            )

            return .updated
        } else {
            // Event was deleted from calendar - recreate
            logger.debug("Event not found in calendar, recreating: \(icsEvent.uid)")

            let newEvent = try await calendarManager.createEvent(from: icsEvent, in: calendar, config: mappingConfig)

            try await stateStore.upsertEvent(
                uid: icsEvent.uid,
                calendarItemId: newEvent.calendarItemExternalIdentifier ?? "",
                eventIdentifier: newEvent.eventIdentifier,
                contentHash: newHash,
                sequence: icsEvent.sequence,
                lastModified: icsEvent.lastModified,
                icsData: icsEvent.rawData
            )

            return .recreated
        }
    }

    private func processNewEvent(
        icsEvent: ICSEvent,
        calendar: EKCalendar,
        mappingConfig: EventMapper.MappingConfig,
        dryRun: Bool
    ) async throws {
        // Bulletproof check: search ENTIRE calendar by ICS UID embedded in notes
        var existingEvent = await calendarManager.findEvent(byICSUID: icsEvent.uid, in: calendar)

        // Fallback: check by matching properties (for legacy events without UID marker)
        if existingEvent == nil {
            existingEvent = await calendarManager.findEvent(matching: icsEvent, in: calendar, config: mappingConfig)
        }

        // If event already exists, update instead of creating duplicate
        if let existingEvent = existingEvent {
            logger.info("Found existing event, updating instead of creating: \(icsEvent.displayTitle)")

            if !dryRun {
                try await calendarManager.updateEvent(existingEvent, from: icsEvent, config: mappingConfig)
                let contentHash = ContentHash.calculate(for: icsEvent)

                try await stateStore.upsertEvent(
                    uid: icsEvent.uid,
                    calendarItemId: existingEvent.calendarItemExternalIdentifier ?? "",
                    eventIdentifier: existingEvent.eventIdentifier,
                    contentHash: contentHash,
                    sequence: icsEvent.sequence,
                    lastModified: icsEvent.lastModified,
                    icsData: icsEvent.rawData
                )
            }
            return
        }

        logger.info("Creating: \(icsEvent.displayTitle)")

        if dryRun {
            return
        }

        let newEvent = try await calendarManager.createEvent(from: icsEvent, in: calendar, config: mappingConfig)
        let contentHash = ContentHash.calculate(for: icsEvent)

        try await stateStore.upsertEvent(
            uid: icsEvent.uid,
            calendarItemId: newEvent.calendarItemExternalIdentifier ?? "",
            eventIdentifier: newEvent.eventIdentifier,
            contentHash: contentHash,
            sequence: icsEvent.sequence,
            lastModified: icsEvent.lastModified,
            icsData: icsEvent.rawData
        )
    }

    private func processDeletedEvent(
        uid: String,
        currentState: [String: SyncedEventRecord],
        dryRun: Bool
    ) async throws {
        guard let state = currentState[uid] else { return }

        logger.info("Deleting orphan: \(uid)")

        if dryRun {
            return
        }

        // Try to find and delete the event
        if let event = await calendarManager.findEvent(byExternalId: state.calendarItemId) {
            try await calendarManager.deleteEvent(event)
        }

        try await stateStore.deleteEvent(uid: uid)
    }

    // MARK: - Calendar Management

    private func getOrCreateCalendar() async throws -> EKCalendar {
        let calendarName = config.destination.calendarName

        if let existing = await calendarManager.findCalendar(named: calendarName) {
            return existing
        }

        guard config.destination.createIfMissing else {
            throw CalendarError.calendarNotFound(calendarName)
        }

        logger.info("Creating calendar: \(calendarName)")
        return try await calendarManager.createCalendar(
            named: calendarName,
            sourcePreference: config.getSourcePreference()
        )
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
