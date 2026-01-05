import EventKit
import Foundation

// MARK: - Event Mapper

/// Maps ICS events to EventKit events and vice versa
enum EventMapper {
    // MARK: - ICS to EKEvent

    /// Apply ICS event properties to an EKEvent
    static func apply(_ icsEvent: ICSEvent, to ekEvent: EKEvent, config: MappingConfig = MappingConfig()) {
        // Basic properties
        ekEvent.title = config.summaryPrefix + (icsEvent.summary ?? "(No Title)")
        ekEvent.notes = buildNotes(from: icsEvent, config: config)
        ekEvent.location = icsEvent.location
        ekEvent.url = icsEvent.url

        // Date/time
        ekEvent.startDate = icsEvent.startDate
        ekEvent.endDate = icsEvent.endDate
        ekEvent.isAllDay = icsEvent.isAllDay

        // Timezone
        if let tz = icsEvent.timeZone {
            ekEvent.timeZone = tz
        }

        // Recurrence rules
        if let rrule = icsEvent.recurrenceRule {
            if let rule = RecurrenceMapper.parseRRule(rrule, startDate: icsEvent.startDate) {
                ekEvent.recurrenceRules = [rule]
            }
        } else {
            ekEvent.recurrenceRules = nil
        }

        // Alarms
        if config.syncAlarms {
            ekEvent.alarms = icsEvent.alarms.compactMap { mapAlarm($0) }
        }

        // Availability (transparency)
        if let transparency = icsEvent.transparency {
            switch transparency {
            case .opaque:
                ekEvent.availability = .busy
            case .transparent:
                ekEvent.availability = .free
            }
        }

        // Note: EKEvent.status is read-only in EventKit
        // The status is determined by the calendar service, not settable by the client
    }

    /// Create a new EKEvent from ICS event
    static func createEKEvent(
        from icsEvent: ICSEvent,
        in calendar: EKCalendar,
        eventStore: EKEventStore,
        config: MappingConfig = MappingConfig()
    ) -> EKEvent {
        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.calendar = calendar
        apply(icsEvent, to: ekEvent, config: config)
        return ekEvent
    }

    // MARK: - EKEvent to ICS

    /// Convert EKEvent back to ICSEvent (for comparison/debugging)
    static func toICSEvent(_ ekEvent: EKEvent) -> ICSEvent {
        ICSEvent(
            uid: ekEvent.calendarItemExternalIdentifier ?? UUID().uuidString,
            summary: ekEvent.title,
            description: ekEvent.notes,
            location: ekEvent.location,
            url: ekEvent.url,
            startDate: ekEvent.startDate,
            endDate: ekEvent.endDate,
            isAllDay: ekEvent.isAllDay,
            sequence: 0,
            lastModified: ekEvent.lastModifiedDate,
            dateStamp: nil,
            recurrenceRule: ekEvent.recurrenceRules?.first.map { RecurrenceMapper.toRRule($0) },
            exceptionDates: [],
            recurrenceDates: [],
            alarms: ekEvent.alarms?.compactMap { mapEKAlarm($0) } ?? [],
            status: mapEKStatus(ekEvent.status),
            transparency: mapEKAvailability(ekEvent.availability),
            organizer: ekEvent.organizer.map { ICSOrganizer(name: $0.name, email: nil) },
            attendees: ekEvent.attendees?.compactMap { mapEKAttendee($0) } ?? [],
            categories: [],
            priority: nil,
            rawData: "",
            timeZone: ekEvent.timeZone
        )
    }

    // MARK: - Configuration

    struct MappingConfig {
        /// Prefix to add to event summaries
        var summaryPrefix: String = ""

        /// Whether to sync alarms
        var syncAlarms: Bool = true

        /// Whether to include source info in notes
        var includeSourceInfo: Bool = false

        /// Source URL for reference
        var sourceURL: URL?

        init() {}
    }

    // MARK: - UID Marker

    /// Marker format for embedding ICS UID in event notes (for bulletproof deduplication)
    private static let uidMarkerPrefix = "[ICS-SYNC-UID:"
    private static let uidMarkerSuffix = "]"

    /// Extract ICS UID from event notes if present
    static func extractUID(from notes: String?) -> String? {
        guard let notes = notes else { return nil }

        guard let startRange = notes.range(of: uidMarkerPrefix),
              let endRange = notes.range(of: uidMarkerSuffix, range: startRange.upperBound..<notes.endIndex) else {
            return nil
        }

        return String(notes[startRange.upperBound..<endRange.lowerBound])
    }

    /// Check if notes contain a UID marker
    static func containsUIDMarker(_ notes: String?) -> Bool {
        guard let notes = notes else { return false }
        return notes.contains(uidMarkerPrefix)
    }

    // MARK: - Private Helpers

    private static func buildNotes(from event: ICSEvent, config: MappingConfig) -> String {
        var notes = event.description ?? ""

        // Always append UID marker for bulletproof deduplication
        // This allows us to find the event even if EventKit identifiers change
        if !notes.isEmpty {
            notes += "\n\n"
        }
        notes += "\(uidMarkerPrefix)\(event.uid)\(uidMarkerSuffix)"

        if config.includeSourceInfo {
            notes += "\n---\n"
            notes += "Synced from: \(config.sourceURL?.absoluteString ?? "ICS feed")"
        }

        return notes
    }

    private static func mapAlarm(_ alarm: ICSAlarm) -> EKAlarm? {
        // EKAlarm uses negative offset for before event
        let offset = alarm.trigger

        // Only support relative alarms to start
        if alarm.triggerRelation == .start {
            return EKAlarm(relativeOffset: offset)
        } else {
            // For end-relative, we'd need event duration - not directly supported
            // Fall back to start-relative
            return EKAlarm(relativeOffset: offset)
        }
    }

    private static func mapEKAlarm(_ alarm: EKAlarm) -> ICSAlarm? {
        guard alarm.relativeOffset != 0 || alarm.absoluteDate == nil else {
            return nil
        }

        return ICSAlarm(
            action: .display,
            trigger: alarm.relativeOffset,
            triggerRelation: .start,
            description: nil
        )
    }

    private static func mapEKStatus(_ status: EKEventStatus) -> EventStatus? {
        switch status {
        case .none: return nil
        case .confirmed: return .confirmed
        case .tentative: return .tentative
        case .canceled: return .cancelled
        @unknown default: return nil
        }
    }

    private static func mapEKAvailability(_ availability: EKEventAvailability) -> EventTransparency? {
        switch availability {
        case .busy, .unavailable: return .opaque
        case .free, .tentative: return .transparent
        case .notSupported: return nil
        @unknown default: return nil
        }
    }

    private static func mapEKAttendee(_ participant: EKParticipant) -> ICSAttendee? {
        var attendee = ICSAttendee()
        attendee.name = participant.name
        attendee.email = participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")

        switch participant.participantRole {
        case .chair: attendee.role = .chair
        case .required: attendee.role = .required
        case .optional: attendee.role = .optional
        case .nonParticipant: attendee.role = .nonParticipant
        case .unknown: attendee.role = nil
        @unknown default: attendee.role = nil
        }

        switch participant.participantStatus {
        case .accepted: attendee.participationStatus = .accepted
        case .declined: attendee.participationStatus = .declined
        case .tentative: attendee.participationStatus = .tentative
        case .delegated: attendee.participationStatus = .delegated
        case .pending: attendee.participationStatus = .needsAction
        case .unknown, .completed, .inProcess:
            attendee.participationStatus = nil
        @unknown default:
            attendee.participationStatus = nil
        }

        return attendee
    }
}

// MARK: - Event Comparison

extension EventMapper {
    /// Check if EKEvent matches ICSEvent (for determining if update needed)
    static func matches(_ ekEvent: EKEvent, _ icsEvent: ICSEvent, config: MappingConfig = MappingConfig()) -> Bool {
        // Compare key fields
        let expectedTitle = config.summaryPrefix + (icsEvent.summary ?? "(No Title)")

        guard ekEvent.title == expectedTitle else { return false }
        guard ekEvent.startDate == icsEvent.startDate else { return false }
        guard ekEvent.endDate == icsEvent.endDate else { return false }
        guard ekEvent.isAllDay == icsEvent.isAllDay else { return false }
        guard ekEvent.location == icsEvent.location else { return false }

        // Notes comparison is tricky due to source info
        if !config.includeSourceInfo {
            guard ekEvent.notes == icsEvent.description else { return false }
        }

        return true
    }
}
