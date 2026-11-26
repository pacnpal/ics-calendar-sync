import Foundation

// MARK: - ICS Parser

/// Parser for ICS (iCalendar) format files
actor ICSParser {
    private let logger = Logger.shared

    // MARK: - Public API

    /// Parse ICS content string into events
    func parse(_ icsContent: String) throws -> [ICSEvent] {
        logger.debug("Starting ICS parsing")

        // Handle line unfolding (RFC 5545: lines starting with space/tab are continuations)
        let unfoldedContent = unfoldLines(icsContent)

        var events: [ICSEvent] = []
        var currentEventLines: [String] = []
        var inEvent = false

        for line in unfoldedContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !trimmed.isEmpty else { continue }

            if trimmed == "BEGIN:VEVENT" {
                inEvent = true
                currentEventLines = []
                continue
            }

            if trimmed == "END:VEVENT" {
                if inEvent {
                    do {
                        let event = try parseEvent(from: currentEventLines)
                        events.append(event)
                    } catch {
                        logger.warning("Failed to parse event: \(error.localizedDescription)")
                    }
                }
                inEvent = false
                currentEventLines = []
                continue
            }

            if inEvent {
                // Include all lines (including alarm boundaries) for parsing
                currentEventLines.append(line)
            }
        }

        logger.debug("Parsed \(events.count) events from ICS")
        return events
    }

    // MARK: - Line Unfolding

    /// Unfold continued lines per RFC 5545
    private func unfoldLines(_ content: String) -> String {
        // Normalize line endings
        var normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Unfold lines that start with space or tab
        normalized = normalized.replacingOccurrences(of: "\n ", with: "")
        normalized = normalized.replacingOccurrences(of: "\n\t", with: "")

        return normalized
    }

    // MARK: - Event Parsing

    /// Parse lines into an ICSEvent
    private func parseEvent(from lines: [String]) throws -> ICSEvent {
        var properties: [String: PropertyValue] = [:]
        var alarmLines: [[String]] = []
        var currentAlarmLines: [String]?
        var rawLines: [String] = ["BEGIN:VEVENT"]

        for line in lines {
            rawLines.append(line)

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "BEGIN:VALARM" {
                currentAlarmLines = []
                continue
            }

            if trimmed == "END:VALARM" {
                if let alarmContent = currentAlarmLines {
                    alarmLines.append(alarmContent)
                }
                currentAlarmLines = nil
                continue
            }

            if currentAlarmLines != nil {
                currentAlarmLines?.append(trimmed)
                continue
            }

            // Parse property
            if let (key, value) = parseProperty(trimmed) {
                // Handle multiple values for same property (e.g., ATTENDEE, EXDATE)
                if let existing = properties[key] {
                    var combined = existing
                    combined.additionalValues.append(contentsOf: [value.value] + value.additionalValues)
                    properties[key] = combined
                } else {
                    properties[key] = value
                }
            }
        }

        rawLines.append("END:VEVENT")

        // Extract required fields
        guard let uid = properties["UID"]?.value else {
            throw ICSError.missingUID
        }

        guard let start = properties["DTSTART"],
              let startDate = parseDateTime(start.value, params: start.params) else {
            throw ICSError.invalidStartDate
        }

        // Determine if all-day event
        let isAllDay = start.params["VALUE"]?.uppercased() == "DATE"

        let startZone = resolvedTimeZone(for: start.value, params: start.params)
        var endZone = startZone

        // Calculate end date
        let endDate: Date
        if let end = properties["DTEND"], let dtend = parseDateTime(end.value, params: end.params) {
            endDate = dtend
            endZone = resolvedTimeZone(for: end.value, params: end.params)
        } else if let duration = properties["DURATION"]?.value {
            endDate = addDuration(duration, to: startDate, timeZone: startZone)
        } else if isAllDay {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = startZone
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        } else {
            // Timed events default to same as start
            endDate = startDate
        }

        // Parse alarms
        let alarms = alarmLines.compactMap {
            parseAlarm(from: $0, start: (startDate, startZone), end: (endDate, endZone))
        }

        // Parse exception dates
        let exceptionDates = parseMultipleDates(properties["EXDATE"])

        // Parse recurrence dates
        let recurrenceDates = parseMultipleDates(properties["RDATE"])

        // Parse attendees
        let attendees = parseAttendees(properties)

        // Parse organizer
        let organizer = parseOrganizer(properties["ORGANIZER"])

        // Parse categories
        let categories = properties["CATEGORIES"]?.value
            .components(separatedBy: ",")
            .map { $0.trimmed.icsUnescaped } ?? []

        // Parse optional values
        var eventURL: URL? = nil
        if let urlString = properties["URL"]?.value {
            eventURL = URL(string: urlString)
        }

        var eventStatus: EventStatus? = nil
        if let statusString = properties["STATUS"]?.value {
            eventStatus = EventStatus(icsValue: statusString)
        }

        var eventTransparency: EventTransparency? = nil
        if let transpString = properties["TRANSP"]?.value {
            eventTransparency = EventTransparency(icsValue: transpString)
        }

        var eventPriority: Int? = nil
        if let priorityString = properties["PRIORITY"]?.value {
            eventPriority = Int(priorityString)
        }

        return ICSEvent(
            uid: uid,
            summary: properties["SUMMARY"]?.value.icsUnescaped,
            description: properties["DESCRIPTION"]?.value.icsUnescaped,
            location: properties["LOCATION"]?.value.icsUnescaped,
            url: eventURL,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            sequence: Int(properties["SEQUENCE"]?.value ?? "0") ?? 0,
            lastModified: parseDateTime(properties["LAST-MODIFIED"]?.value, params: nil),
            dateStamp: parseDateTime(properties["DTSTAMP"]?.value, params: nil),
            recurrenceRule: properties["RRULE"]?.value,
            exceptionDates: exceptionDates,
            recurrenceDates: recurrenceDates,
            alarms: alarms,
            status: eventStatus,
            transparency: eventTransparency,
            organizer: organizer,
            attendees: attendees,
            categories: categories,
            priority: eventPriority,
            rawData: rawLines.joined(separator: "\r\n"),
            timeZone: extractTimeZone(from: start.params)
        )
    }

    // MARK: - Property Parsing

    /// Represents a parsed property with value and parameters
    private struct PropertyValue {
        var value: String
        var params: [String: String]
        var additionalValues: [String] = []
    }

    /// Parse a single property line into key and value with parameters
    private func parseProperty(_ line: String) -> (String, PropertyValue)? {
        // Find the colon that separates property name/params from value
        guard let colonIndex = findPropertyValueSeparator(in: line) else {
            return nil
        }

        let keyPart = String(line[..<colonIndex])
        let value = String(line[line.index(after: colonIndex)...])

        // Parse property name and parameters
        var inQuotes = false
        let components = keyPart.split { character in
            if character == "\"" { inQuotes.toggle() }
            return character == ";" && !inQuotes
        }
        guard let propertyName = components.first?.uppercased() else {
            return nil
        }

        var params: [String: String] = [:]
        for param in components.dropFirst() {
            guard let equals = param.firstIndex(of: "=") else { continue }
            let name = param[..<equals].uppercased()
            let value = param[param.index(after: equals)...]
            params[name] = String(value).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        return (propertyName, PropertyValue(value: value, params: params))
    }

    /// Find the colon that separates property from value (handling quoted params)
    private func findPropertyValueSeparator(in line: String) -> String.Index? {
        var inQuotes = false

        for (index, char) in line.enumerated() {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == ":" && !inQuotes {
                return line.index(line.startIndex, offsetBy: index)
            }
        }

        return nil
    }

    // MARK: - Date/Time Parsing

    /// Parse ICS date/time value with optional timezone
    private func parseDateTime(_ value: String?, params: [String: String]?) -> Date? {
        guard let value = value else { return nil }

        let dateValue = value.hasSuffix("Z") ? String(value.dropLast()) : value
        let timeZone = resolvedTimeZone(for: value, params: params)

        // Try different formats
        let formats = [
            "yyyyMMdd'T'HHmmss",     // 20240101T090000
            "yyyyMMdd'T'HHmm",       // 20240101T0900
            "yyyyMMdd",              // 20240101 (all-day)
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone

            if let date = formatter.date(from: dateValue) {
                return date
            }
        }

        return nil
    }

    private func resolvedTimeZone(for value: String, params: [String: String]?) -> TimeZone {
        value.hasSuffix("Z") ? .gmt : extractTimeZone(from: params) ?? .current
    }

    /// Parse timezone identifier, handling non-standard formats
    private func parseOlsonTimezone(_ tzid: String) -> TimeZone? {
        // Handle common non-standard timezone names
        let mappings: [String: String] = [
            "Eastern Standard Time": "America/New_York",
            "Pacific Standard Time": "America/Los_Angeles",
            "Central Standard Time": "America/Chicago",
            "Mountain Standard Time": "America/Denver",
            "GMT": "UTC",
            "Etc/GMT": "UTC",
        ]

        if let mapped = mappings[tzid] {
            return TimeZone(identifier: mapped)
        }

        // Try removing common prefixes
        let cleaned = tzid
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "/Microsoft/", with: "")

        return TimeZone(identifier: cleaned)
    }

    /// Extract timezone from parameters
    private func extractTimeZone(from params: [String: String]?) -> TimeZone? {
        guard let tzid = params?["TZID"] else { return nil }
        return TimeZone(identifier: tzid) ?? parseOlsonTimezone(tzid)
    }

    /// Parse multiple dates from a property (for EXDATE, RDATE)
    private func parseMultipleDates(_ property: PropertyValue?) -> [Date] {
        guard let property = property else { return [] }

        var dates: [Date] = []
        let allValues = [property.value] + property.additionalValues

        for value in allValues {
            // Values can be comma-separated
            let dateStrings = value.components(separatedBy: ",")
            for dateString in dateStrings {
                if let date = parseDateTime(dateString.trimmed, params: property.params) {
                    dates.append(date)
                }
            }
        }

        return dates
    }

    // MARK: - Duration Parsing

    /// Add ICS duration to date
    private func addDuration(_ duration: String, to date: Date, timeZone: TimeZone) -> Date {
        // Parse ISO 8601 duration format: P[n]Y[n]M[n]DT[n]H[n]M[n]S
        // Examples: PT1H (1 hour), P1D (1 day), PT30M (30 minutes)

        var result = date
        var durationStr = duration.uppercased()

        var calendar = Calendar.current
        calendar.timeZone = timeZone
        if durationStr.hasPrefix("+") { durationStr.removeFirst() }
        guard durationStr.hasPrefix("P") else { return date }
        durationStr = String(durationStr.dropFirst())

        var isTimePart = false
        var currentNumber = ""

        for char in durationStr {
            if char == "T" {
                isTimePart = true
                continue
            }

            if char.isNumber || char == "-" {
                currentNumber.append(char)
                continue
            }

            guard let value = Int(currentNumber) else {
                currentNumber = ""
                continue
            }

            let component: Calendar.Component
            switch char {
            case "Y": component = .year
            case "M": component = isTimePart ? .minute : .month
            case "W": component = .weekOfYear
            case "D": component = .day
            case "H": component = .hour
            case "S": component = .second
            default:
                currentNumber = ""
                continue
            }

            if let newDate = calendar.date(byAdding: component, value: value, to: result) {
                result = newDate
            }

            currentNumber = ""
        }

        return result
    }

    // MARK: - Alarm Parsing

    private let absoluteAlarmFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private typealias AlarmAnchor = (date: Date, timeZone: TimeZone)

    private func parseAlarm(from lines: [String], start: AlarmAnchor, end: AlarmAnchor) -> ICSAlarm? {
        var properties: [String: PropertyValue] = [:]
        for line in lines {
            if let (name, property) = parseProperty(line) {
                properties[name] = property
            }
        }

        guard let actionValue = properties["ACTION"]?.value,
              let action = ICSAlarm.AlarmAction(icsValue: actionValue),
              let trigger = properties["TRIGGER"] else { return nil }

        let description = properties["DESCRIPTION"]?.value.icsUnescaped
        let value = trigger.value.uppercased()
        switch trigger.params["VALUE"]?.uppercased() ?? "DURATION" {
        case "DATE-TIME":
            // RFC 5545 requires a complete UTC timestamp for an absolute trigger.
            guard let date = absoluteAlarmFormatter.date(from: value),
                  absoluteAlarmFormatter.string(from: date) == value else { return nil }
            return ICSAlarm(action: action, trigger: 0, triggerRelation: .start,
                            description: description, absoluteDate: date)
        case "DURATION":
            let relation: ICSAlarm.TriggerRelation
            switch trigger.params["RELATED"]?.uppercased() ?? "START" {
            case "START": relation = .start
            case "END": relation = .end
            default: return nil
            }
            let anchor = relation == .end ? end : start
            guard let offset = parseDurationToSeconds(value, from: anchor) else { return nil }
            return ICSAlarm(action: action, trigger: offset, triggerRelation: relation, description: description)
        default:
            return nil
        }
    }

    /// Parse a signed iCalendar duration, keeping malformed input distinct from PT0S.
    private func parseDurationToSeconds(_ value: String, from anchor: AlarmAnchor) -> TimeInterval? {
        let pattern = #/
            ([+-]?) P
            (?:
                ([0-9]+) W
                |
                (?: ([0-9]+) D )?
                (?: T (?: ([0-9]+) H )? (?: ([0-9]+) M )? (?: ([0-9]+) S )? )?
            )
            /#
        guard !value.hasSuffix("P"), !value.hasSuffix("T"),
              let match = value.wholeMatch(of: pattern) else { return nil }

        let (_, sign, weeks, days, hours, minutes, seconds) = match.output
        // A calendar day can span 23 or 25 hours. Apply nominal units before clock units.
        var total: TimeInterval = 0
        if let digits = weeks ?? days {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = anchor.timeZone
            guard let count = Int(digits),
                  let date = calendar.date(byAdding: weeks == nil ? .day : .weekOfYear,
                                           value: sign == "-" ? -count : count, to: anchor.date) else { return nil }
            total = abs(date.timeIntervalSince(anchor.date))
        }
        let components: [(Substring?, TimeInterval)] = [(hours, 3600), (minutes, 60), (seconds, 1)]
        for (digits, scale) in components {
            if let digits {
                guard let number = TimeInterval(digits) else { return nil }
                total += number * scale
            }
        }
        guard total.isFinite else { return nil }
        return sign == "-" ? -total : total
    }

    // MARK: - Attendee/Organizer Parsing

    /// Parse attendees from properties
    private func parseAttendees(_ properties: [String: PropertyValue]) -> [ICSAttendee] {
        // ATTENDEE lines are stored with additional values
        guard let attendeeProperty = properties["ATTENDEE"] else { return [] }

        var attendees: [ICSAttendee] = []

        // Parse each attendee value
        // Format: ATTENDEE;ROLE=REQ-PARTICIPANT;CN=Name:mailto:email@example.com

        // We need to re-parse from raw to get parameters per attendee
        // For now, simplified parsing
        let allValues = [attendeeProperty.value] + attendeeProperty.additionalValues

        for value in allValues {
            var attendee = ICSAttendee()

            // Extract email from mailto:
            if value.lowercased().hasPrefix("mailto:") {
                attendee.email = String(value.dropFirst(7))
            } else {
                attendee.email = value
            }

            attendees.append(attendee)
        }

        return attendees
    }

    /// Parse organizer from property
    private func parseOrganizer(_ property: PropertyValue?) -> ICSOrganizer? {
        guard let property = property else { return nil }

        var organizer = ICSOrganizer()

        // Extract name from CN parameter
        organizer.name = property.params["CN"]

        // Extract email from value
        let value = property.value
        if value.lowercased().hasPrefix("mailto:") {
            organizer.email = String(value.dropFirst(7))
        } else {
            organizer.email = value
        }

        return organizer
    }
}

// MARK: - ICS Calendar Container

/// Represents a parsed ICS file with metadata
struct ICSCalendar: Sendable {
    var productId: String?
    var version: String?
    var calendarName: String?
    var timeZone: TimeZone?
    var events: [ICSEvent]

    init(events: [ICSEvent] = []) {
        self.events = events
    }
}
