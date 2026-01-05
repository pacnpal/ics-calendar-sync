import EventKit
import Foundation

// MARK: - Calendar Manager

/// Manages EventKit operations for calendar sync
actor CalendarManager {
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
            // Write-only might work for our purposes
            accessGranted = true
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return false
        @unknown default:
            return false
        }
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

    /// Find event by external identifier (stable across app restarts)
    func findEvent(byExternalId id: String) -> EKEvent? {
        eventStore.calendarItem(withIdentifier: id) as? EKEvent
    }

    /// Find event by event identifier
    func findEvent(byEventId id: String) -> EKEvent? {
        eventStore.event(withIdentifier: id)
    }

    /// Find event by ICS UID embedded in notes (bulletproof deduplication)
    /// This searches ALL events in the calendar for the UID marker
    /// We search the entire calendar because the event's date may have changed
    func findEvent(byICSUID uid: String, in calendar: EKCalendar) -> EKEvent? {
        // Search entire calendar - use wide but reasonable range (5 years back, 5 years forward)
        // Note: EventKit doesn't handle extremely wide ranges (100+ years) - returns 0 events
        let searchStart = Date().addingTimeInterval(-5 * 365 * 24 * 60 * 60)
        let searchEnd = Date().addingTimeInterval(5 * 365 * 24 * 60 * 60)

        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: [calendar]
        )

        let events = eventStore.events(matching: predicate)

        // Find event with matching UID in notes
        if let found = events.first(where: { EventMapper.extractUID(from: $0.notes) == uid }) {
            logger.debug("Found event by UID marker: \(found.title ?? "(No Title)")")
            return found
        }
        return nil
    }

    /// Find event by matching properties (title and start date) in a specific calendar
    /// This is a fallback for legacy events that don't have the UID marker
    /// Uses fuzzy matching: title contains expected text, times within 5 minutes
    /// IMPORTANT: Only matches events that DON'T have a different UID marker (to avoid stealing other synced events)
    func findEvent(matching icsEvent: ICSEvent, in calendar: EKCalendar, config: EventMapper.MappingConfig = EventMapper.MappingConfig()) -> EKEvent? {
        // Search in a wider window to catch timezone edge cases
        let searchStart = icsEvent.startDate.addingTimeInterval(-86400 * 2) // 2 days before
        let searchEnd = icsEvent.startDate.addingTimeInterval(86400 * 2)    // 2 days after

        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: [calendar]
        )

        let events = eventStore.events(matching: predicate)
        let expectedTitle = config.summaryPrefix + (icsEvent.summary ?? "(No Title)")
        let timeTolerance: TimeInterval = 300 // 5 minutes

        // First pass: try exact UID match in notes
        if let exactMatch = events.first(where: { EventMapper.extractUID(from: $0.notes) == icsEvent.uid }) {
            logger.debug("Found event by UID in property search: \(exactMatch.title ?? "(No Title)")")
            return exactMatch
        }

        // Second pass: fuzzy property matching for events WITHOUT a different UID marker
        let fuzzyMatch = events.first { event in
            // Check if this event has a UID marker
            let existingUID = EventMapper.extractUID(from: event.notes)

            // If event has a DIFFERENT UID marker, it belongs to another ICS event - don't touch it!
            if existingUID != nil && existingUID != icsEvent.uid {
                return false
            }

            // Event has NO UID marker or has OUR UID - safe to match by properties
            // Use fuzzy matching for legacy events

            // Title: check if either contains the other (case-insensitive)
            let eventTitle = event.title?.lowercased() ?? ""
            let expected = expectedTitle.lowercased()
            let titleMatch = eventTitle == expected ||
                             eventTitle.contains(expected) ||
                             expected.contains(eventTitle)

            guard titleMatch else { return false }

            // isAllDay must match exactly
            guard event.isAllDay == icsEvent.isAllDay else { return false }

            // Times: within tolerance (handles slight timezone/rounding differences)
            let startDiff = abs(event.startDate.timeIntervalSince(icsEvent.startDate))
            let endDiff = abs(event.endDate.timeIntervalSince(icsEvent.endDate))

            return startDiff <= timeTolerance && endDiff <= timeTolerance
        }

        if let found = fuzzyMatch {
            logger.debug("Found event by fuzzy match: \(found.title ?? "(No Title)")")
        }
        return fuzzyMatch
    }

    /// Get all events in a calendar within date range
    func getEvents(in calendar: EKCalendar, from startDate: Date, to endDate: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: [calendar]
        )
        return eventStore.events(matching: predicate)
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
