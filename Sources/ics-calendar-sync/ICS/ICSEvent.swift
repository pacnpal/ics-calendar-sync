import Foundation

// MARK: - ICS Event

/// Represents a parsed VEVENT from an ICS file
struct ICSEvent: Sendable, Equatable {
    /// Unique identifier from the ICS (UID property)
    let uid: String

    /// Event summary/title (SUMMARY property)
    var summary: String?

    /// Event description (DESCRIPTION property)
    var description: String?

    /// Event location (LOCATION property)
    var location: String?

    /// Event URL (URL property)
    var url: URL?

    /// Start date/time (DTSTART property)
    var startDate: Date

    /// End date/time (DTEND property)
    var endDate: Date

    /// Whether this is an all-day event
    var isAllDay: Bool

    /// Sequence number for change detection (SEQUENCE property)
    var sequence: Int

    /// Last modified timestamp (LAST-MODIFIED property)
    var lastModified: Date?

    /// DTSTAMP property
    var dateStamp: Date?

    /// Raw RRULE string for recurring events
    var recurrenceRule: String?

    /// Exception dates for recurring events (EXDATE)
    var exceptionDates: [Date]

    /// Additional recurrence dates (RDATE)
    var recurrenceDates: [Date]

    /// Alarms associated with this event
    var alarms: [ICSAlarm]

    /// Event status (CONFIRMED, TENTATIVE, CANCELLED)
    var status: EventStatus?

    /// Transparency (OPAQUE, TRANSPARENT)
    var transparency: EventTransparency?

    /// Organizer information
    var organizer: ICSOrganizer?

    /// Attendees
    var attendees: [ICSAttendee]

    /// Categories/tags
    var categories: [String]

    /// Event priority (1-9, 1 highest)
    var priority: Int?

    /// Original VEVENT block for storage/debugging
    var rawData: String

    /// Timezone identifier for the event
    var timeZone: TimeZone?
}

// MARK: - Event Status

/// Status of an event
enum EventStatus: String, Sendable {
    case tentative = "TENTATIVE"
    case confirmed = "CONFIRMED"
    case cancelled = "CANCELLED"

    init?(icsValue: String) {
        self.init(rawValue: icsValue.uppercased())
    }
}

// MARK: - Event Transparency

/// How event affects free/busy time
enum EventTransparency: String, Sendable {
    case opaque = "OPAQUE"       // Blocks time
    case transparent = "TRANSPARENT"  // Does not block time

    init?(icsValue: String) {
        self.init(rawValue: icsValue.uppercased())
    }
}

// MARK: - ICS Alarm

/// Represents a VALARM component
struct ICSAlarm: Sendable, Equatable {
    /// Action type (DISPLAY, AUDIO, EMAIL)
    let action: AlarmAction

    /// Trigger time relative to event (negative = before)
    let trigger: TimeInterval

    /// Whether trigger is relative to start or end
    let triggerRelation: TriggerRelation

    /// Optional alarm description
    var description: String?

    enum AlarmAction: String, Sendable {
        case display = "DISPLAY"
        case audio = "AUDIO"
        case email = "EMAIL"

        init?(icsValue: String) {
            self.init(rawValue: icsValue.uppercased())
        }
    }

    enum TriggerRelation: Sendable {
        case start
        case end
    }
}

// MARK: - ICS Organizer

/// Represents event organizer
struct ICSOrganizer: Sendable, Equatable {
    var name: String?
    var email: String?

    init(name: String? = nil, email: String? = nil) {
        self.name = name
        self.email = email
    }
}

// MARK: - ICS Attendee

/// Represents an event attendee
struct ICSAttendee: Sendable, Equatable {
    var name: String?
    var email: String?
    var role: AttendeeRole?
    var participationStatus: ParticipationStatus?
    var rsvp: Bool?

    enum AttendeeRole: String, Sendable {
        case chair = "CHAIR"
        case required = "REQ-PARTICIPANT"
        case optional = "OPT-PARTICIPANT"
        case nonParticipant = "NON-PARTICIPANT"

        init?(icsValue: String) {
            self.init(rawValue: icsValue.uppercased())
        }
    }

    enum ParticipationStatus: String, Sendable {
        case needsAction = "NEEDS-ACTION"
        case accepted = "ACCEPTED"
        case declined = "DECLINED"
        case tentative = "TENTATIVE"
        case delegated = "DELEGATED"

        init?(icsValue: String) {
            self.init(rawValue: icsValue.uppercased())
        }
    }
}

// MARK: - ICS Event Extensions

extension ICSEvent {
    /// Duration of the event
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    /// Check if event is recurring
    var isRecurring: Bool {
        recurrenceRule != nil
    }

    /// Display-friendly summary
    var displayTitle: String {
        summary ?? "(No Title)"
    }

    /// Date range description
    var dateRangeDescription: String {
        let formatter = DateFormatter()

        if isAllDay {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none

            if Calendar.current.isDate(startDate, inSameDayAs: endDate.addingTimeInterval(-1)) {
                return formatter.string(from: startDate)
            } else {
                return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate.addingTimeInterval(-86400)))"
            }
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                let timeFormatter = DateFormatter()
                timeFormatter.dateStyle = .none
                timeFormatter.timeStyle = .short
                return "\(formatter.string(from: startDate)) - \(timeFormatter.string(from: endDate))"
            } else {
                return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
            }
        }
    }
}

// MARK: - Default Event

extension ICSEvent {
    /// Create a minimal event for testing
    static func minimal(uid: String, summary: String, startDate: Date, endDate: Date) -> ICSEvent {
        ICSEvent(
            uid: uid,
            summary: summary,
            description: nil,
            location: nil,
            url: nil,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            sequence: 0,
            lastModified: nil,
            dateStamp: nil,
            recurrenceRule: nil,
            exceptionDates: [],
            recurrenceDates: [],
            alarms: [],
            status: nil,
            transparency: nil,
            organizer: nil,
            attendees: [],
            categories: [],
            priority: nil,
            rawData: "",
            timeZone: nil
        )
    }
}
