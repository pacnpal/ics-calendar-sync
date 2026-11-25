import EventKit
import Foundation

// MARK: - Calendar Manager

/// Manages EventKit operations for calendar sync
actor CalendarManager: SyncCalendar {
    private let eventStore: EKEventStore
    private let logger = Logger.shared
    private var accessGranted = false

    init() {
        self.eventStore = EKEventStore()
    }

    // MARK: - Access Management

    /// Request calendar access from user
    func requestAccess() async throws {
        logger.debug("Requesting calendar access")

        if #available(macOS 14.0, *) {
            accessGranted = try await eventStore.requestFullAccessToEvents()
        } else {
            accessGranted = try await eventStore.requestAccess(to: .event)
        }

        guard accessGranted else {
            throw CalendarError.accessDenied
        }

        logger.info("Calendar access granted")
    }

    /// Check if access is already granted
    func checkAccess() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            accessGranted = true
            return true
        case .writeOnly:
            return false
        case .denied, .restricted:
            return false
        case .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    /// Async check if calendar access is still valid (re-checks system status)
    func hasAccess() async -> Bool {
        return checkAccess()
    }

    /// Get authorization status description
    func getAuthorizationStatusDescription() -> String {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            return "Full Access"
        case .writeOnly:
            return "Write Only"
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }

    // MARK: - Calendar Discovery

    /// Get all calendars for events
    func getAllCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event)
    }

    /// Get calendars grouped by source
    func getCalendarsGroupedBySource() -> [(source: EKSource, calendars: [EKCalendar])] {
        let calendars = getAllCalendars()
        var grouped: [String: (source: EKSource, calendars: [EKCalendar])] = [:]

        for calendar in calendars {
            let sourceId = calendar.source.sourceIdentifier
            if grouped[sourceId] == nil {
                grouped[sourceId] = (source: calendar.source, calendars: [])
            }
            grouped[sourceId]?.calendars.append(calendar)
        }

        // Sort sources by type preference (iCloud first, then others)
        return grouped.values.sorted { lhs, rhs in
            let lhsScore = sourceTypeScore(lhs.source.sourceType)
            let rhsScore = sourceTypeScore(rhs.source.sourceType)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return lhs.source.title < rhs.source.title
        }
    }

    private func sourceTypeScore(_ type: EKSourceType) -> Int {
        switch type {
        case .calDAV: return 0  // iCloud, Google, etc.
        case .exchange: return 1
        case .mobileMe: return 1  // Legacy
        case .local: return 2
        case .subscribed: return 3
        case .birthdays: return 4
        @unknown default: return 5
        }
    }

    /// Find calendar by name
    func findCalendar(named name: String) -> EKCalendar? {
        eventStore.calendars(for: .event).first { $0.title == name }
    }

    /// Find calendar by identifier
    func findCalendar(withIdentifier identifier: String) -> EKCalendar? {
        eventStore.calendar(withIdentifier: identifier)
    }

    // MARK: - Calendar Management

    /// Create a new calendar
    func createCalendar(named name: String, sourcePreference: SourcePreference = .iCloud) throws -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = name

        // Find appropriate source
        let source = try findSource(preference: sourcePreference)
        calendar.source = source

        try eventStore.saveCalendar(calendar, commit: true)
        logger.info("Created calendar '\(name)' in \(source.title)")
        return calendar
    }

    /// Delete a calendar
    func deleteCalendar(_ calendar: EKCalendar) throws {
        try eventStore.removeCalendar(calendar, commit: true)
        logger.info("Deleted calendar '\(calendar.title)'")
    }

    /// Source preference for calendar creation
    enum SourcePreference: String, Sendable {
        case iCloud = "icloud"
        case local = "local"
        case any = "any"
    }

    private func findSource(preference: SourcePreference) throws -> EKSource {
        let sources = eventStore.sources

        switch preference {
        case .iCloud:
            // Look for iCloud source (CalDAV with "iCloud" title)
            if let iCloud = sources.first(where: {
                $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud")
            }) {
                return iCloud
            }
            // Fall back to any CalDAV
            if let calDAV = sources.first(where: { $0.sourceType == .calDAV }) {
                return calDAV
            }
            // Fall back to local
            if let local = sources.first(where: { $0.sourceType == .local }) {
                return local
            }

        case .local:
            if let local = sources.first(where: { $0.sourceType == .local }) {
                return local
            }

        case .any:
            // Prefer iCloud, then CalDAV, then local
            if let iCloud = sources.first(where: {
                $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud")
            }) {
                return iCloud
            }
            if let calDAV = sources.first(where: { $0.sourceType == .calDAV }) {
                return calDAV
            }
            if let local = sources.first(where: { $0.sourceType == .local }) {
                return local
            }
        }

        throw CalendarError.noSuitableSource
    }

    // MARK: - Event Operations

    /// Create event from ICS data
    func createEvent(from icsEvent: ICSEvent, in calendar: EKCalendar, config: EventMapper.MappingConfig = EventMapper.MappingConfig()) throws -> EKEvent {
        let event = EventMapper.createEKEvent(from: icsEvent, in: calendar, eventStore: eventStore, config: config)
        try eventStore.save(event, span: .futureEvents, commit: true)
        logger.debug("Created event: \(icsEvent.displayTitle)")
        return event
    }

    /// Update existing event
    func updateEvent(_ event: EKEvent, from icsEvent: ICSEvent, config: EventMapper.MappingConfig = EventMapper.MappingConfig()) throws {
        EventMapper.apply(icsEvent, to: event, config: config)
        try eventStore.save(event, span: .futureEvents, commit: true)
        logger.debug("Updated event: \(icsEvent.displayTitle)")
    }

    /// Delete event
    func deleteEvent(_ event: EKEvent) throws {
        let title = event.title ?? "(No Title)"
        try eventStore.remove(event, span: .futureEvents, commit: true)
        logger.debug("Deleted event: \(title)")
    }

    func destination(for config: Configuration, dryRun: Bool) throws -> String? {
        let name = config.destination.calendarName
        let matching = getAllCalendars().filter { $0.title == name }
        guard matching.count <= 1 else {
            throw SyncError.configurationError("Multiple calendars are named '\(name)'. Choose a unique destination name.")
        }
        if let calendar = matching.first { return calendar.calendarIdentifier }
        guard config.destination.createIfMissing else { throw CalendarError.calendarNotFound(name) }
        if dryRun { return nil }
        return try createCalendar(named: name, sourcePreference: config.getSourcePreference()).calendarIdentifier
    }

    func save(_ source: ICSEvent, to item: CalendarItemMatch?, in calendarID: String,
              mapping: EventMapper.MappingConfig) throws -> CalendarItemMatch {
        guard let feed = mapping.feedID,
              item == nil || item?.marker == .owned(feed: feed, uid: source.uid) else {
            throw CalendarError.eventNotFound(source.uid)
        }
        return try write(source, to: item, in: calendarID, mapping: mapping)
    }

    /// Called only for the UID and local item ID explicitly selected in the migration command.
    func adopt(_ source: ICSEvent, item: CalendarItemMatch, in calendarID: String,
               mapping: EventMapper.MappingConfig) throws -> CalendarItemMatch {
        guard item.marker == .legacy(uid: source.uid) || item.marker == .unmarked(uid: source.uid) else {
            throw CalendarError.eventNotFound(source.uid)
        }
        return try write(source, to: item, in: calendarID, mapping: mapping)
    }

    private func write(_ source: ICSEvent, to item: CalendarItemMatch?, in calendarID: String,
                       mapping: EventMapper.MappingConfig) throws -> CalendarItemMatch {
        guard let feed = mapping.feedID else { throw CalendarError.eventNotFound(source.uid) }
        let event: EKEvent
        if let item {
            guard item.calendarID == calendarID else { throw CalendarError.eventNotFound(item.itemID) }
            event = try checkedEvent(item)
            try updateEvent(event, from: source, config: mapping)
        } else {
            guard let calendar = findCalendar(withIdentifier: calendarID) else { throw CalendarError.calendarNotFound(calendarID) }
            event = try createEvent(from: source, in: calendar, config: mapping)
        }
        guard let saved = match(event),
              saved.calendarID == calendarID, saved.marker == .owned(feed: feed, uid: source.uid) else {
            throw CalendarError.eventNotFound(source.uid)
        }
        return saved
    }

    func remove(_ item: CalendarItemMatch) throws {
        guard case .owned = item.marker else { throw CalendarError.eventNotFound(item.itemID) }
        try deleteEvent(checkedEvent(item))
    }

    private func match(_ event: EKEvent, fallback: EventMarker? = nil) -> CalendarItemMatch? {
        guard let marker = EventMarker(notes: event.notes) ?? fallback, let calendar = event.calendar else { return nil }
        return CalendarItemMatch(calendarID: calendar.calendarIdentifier, itemID: event.calendarItemIdentifier,
                                 externalID: event.calendarItemExternalIdentifier, eventID: event.eventIdentifier,
                                 marker: marker, recurring: event.hasRecurrenceRules, detached: event.isDetached)
    }

    /// Scan once per sync. Supplement the normal horizon for explicitly requested distant events.
    func inventory(in calendarID: String, eventDates: [Date]) throws -> [String: [CalendarItemMatch]] {
        guard let calendar = findCalendar(withIdentifier: calendarID) else { throw CalendarError.calendarNotFound(calendarID) }
        let now = Date()
        let horizon = DateInterval(start: now.addingTimeInterval(-5 * 365 * 86400),
                                   end: now.addingTimeInterval(5 * 365 * 86400))
        var events = getEvents(in: calendar, from: horizon.start, to: horizon.end)
        for date in Set(eventDates) where !horizon.contains(date) {
            events += getEvents(in: calendar, from: date.addingTimeInterval(-86400), to: date.addingTimeInterval(86400))
        }
        return Dictionary(grouping: events.compactMap { match($0) }, by: { $0.marker.uid })
    }

    func matches(for uid: String, feed: String, calendar: String, state: SyncedEventRecord?,
                 scanned: [CalendarItemMatch], legacy: SyncStateStore.LegacyIdentifiers? = nil) -> EventMatches {
        func byIdentifiers(_ externalID: String?, _ eventID: String?, fallback: EventMarker? = nil) -> [CalendarItemMatch] {
            var events = [EKEvent]()
            if let id = externalID, !id.isEmpty {
                events = eventStore.calendarItems(withExternalIdentifier: id).compactMap { $0 as? EKEvent }
            }
            if let id = eventID, !id.isEmpty, let event = eventStore.event(withIdentifier: id) {
                events.append(event)
            }
            return events.compactMap { match($0, fallback: fallback) }
        }
        var candidates = scanned + byIdentifiers(state?.calendarItemId, state?.eventIdentifier)
        if let legacy {
            candidates += byIdentifiers(legacy.externalID, legacy.eventID, fallback: .unmarked(uid: uid))
        }
        return EventMatches(candidates: candidates, calendarID: calendar, feed: feed, uid: uid,
                            externalID: state?.calendarItemId, eventID: state?.eventIdentifier)
    }

    /// Re-read the first occurrence and verify the target immediately before each mutation.
    func checkedEvent(_ item: CalendarItemMatch) throws -> EKEvent {
        guard let event = eventStore.calendarItem(withIdentifier: item.itemID) as? EKEvent,
              event.calendar?.calendarIdentifier == item.calendarID, !event.isDetached,
              markerMatches(event, item: item) else {
            throw CalendarError.eventNotFound(item.itemID)
        }
        return event
    }

    private func markerMatches(_ event: EKEvent, item: CalendarItemMatch) -> Bool {
        if case .unmarked = item.marker { return !(event.notes ?? "").contains("[ICS-SYNC-") }
        return EventMarker(notes: event.notes) == item.marker
    }

    func removeDuplicate(_ item: CalendarItemMatch, keeping keeper: CalendarItemMatch) throws {
        let canonical = try checkedEvent(keeper)
        let duplicate = try checkedEvent(item)
        guard case .owned = keeper.marker, canonical.calendarItemIdentifier != duplicate.calendarItemIdentifier,
              item.calendarID == keeper.calendarID, item.marker == keeper.marker,
              !canonical.hasRecurrenceRules, !duplicate.hasRecurrenceRules else {
            throw SyncError.configurationError("Duplicate changed during sync. Retaining both items.")
        }
        try deleteEvent(duplicate)
    }

    func getEvents(in calendar: EKCalendar, from startDate: Date, to endDate: Date) -> [EKEvent] {
        struct Occurrence: Hashable {
            let itemID: String
            let date: Date
        }
        return CalendarQuery.events(from: startDate, to: endDate, key: { (event: EKEvent) in
            Occurrence(itemID: event.calendarItemIdentifier, date: event.occurrenceDate ?? event.startDate)
        }) { chunk in
            let predicate = eventStore.predicateForEvents(withStart: chunk.start, end: chunk.end, calendars: [calendar])
            return eventStore.events(matching: predicate)
        }
    }

    /// Get event count in calendar
    /// Note: EventKit doesn't handle Date.distantPast/distantFuture well, so we use a 10-year window
    func getEventCount(in calendar: EKCalendar) -> Int {
        let startDate = Date().addingTimeInterval(-5 * 365 * 24 * 60 * 60)  // 5 years back
        let endDate = Date().addingTimeInterval(5 * 365 * 24 * 60 * 60)     // 5 years forward
        return getEvents(in: calendar, from: startDate, to: endDate).count
    }

    // MARK: - Batch Operations

    /// Create multiple events efficiently
    func createEvents(from icsEvents: [ICSEvent], in calendar: EKCalendar, config: EventMapper.MappingConfig = EventMapper.MappingConfig()) throws -> [EKEvent] {
        var created: [EKEvent] = []

        for icsEvent in icsEvents {
            let event = EventMapper.createEKEvent(from: icsEvent, in: calendar, eventStore: eventStore, config: config)
            try eventStore.save(event, span: .futureEvents, commit: false)
            created.append(event)
        }

        // Commit all at once
        try eventStore.commit()
        logger.info("Created \(created.count) events in batch")
        return created
    }

    /// Delete multiple events efficiently
    func deleteEvents(_ events: [EKEvent]) throws {
        for event in events {
            try eventStore.remove(event, span: .futureEvents, commit: false)
        }
        try eventStore.commit()
        logger.info("Deleted \(events.count) events in batch")
    }

    /// Refresh event store to get latest data
    func refresh() {
        eventStore.refreshSourcesIfNecessary()
    }
}

// MARK: - Calendar Info

extension CalendarManager {
    /// Get display information about a calendar
    struct CalendarInfo: Sendable {
        let identifier: String
        let title: String
        let sourceName: String
        let sourceType: String
        let color: String
        let isImmutable: Bool
        let allowsContentModifications: Bool
    }

    func getCalendarInfo(_ calendar: EKCalendar) -> CalendarInfo {
        CalendarInfo(
            identifier: calendar.calendarIdentifier,
            title: calendar.title,
            sourceName: calendar.source.title,
            sourceType: sourceTypeDescription(calendar.source.sourceType),
            color: colorToHex(calendar.cgColor),
            isImmutable: calendar.isImmutable,
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    private func sourceTypeDescription(_ type: EKSourceType) -> String {
        switch type {
        case .local: return "Local"
        case .exchange: return "Exchange"
        case .mobileMe: return "MobileMe"
        case .calDAV: return "CalDAV"
        case .subscribed: return "Subscribed"
        case .birthdays: return "Birthdays"
        @unknown default: return "Unknown"
        }
    }

    private func colorToHex(_ color: CGColor?) -> String {
        guard let color = color,
              let components = color.components,
              components.count >= 3 else {
            return "#000000"
        }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
