import EventKit
import Foundation

// MARK: - Recurrence Mapper

/// Maps ICS RRULE strings to EventKit EKRecurrenceRule objects
enum RecurrenceMapper {
    /// Parse RRULE string into EKRecurrenceRule
    static func parseRRule(_ rrule: String, startDate: Date) -> EKRecurrenceRule? {
        let components = parseRRuleComponents(rrule)

        guard let freqStr = components["FREQ"],
              let frequency = parseFrequency(freqStr) else {
            return nil
        }

        // Parse interval (default 1)
        let interval = components["INTERVAL"].flatMap { Int($0) } ?? 1

        // Parse end condition
        let end = parseEnd(components, startDate: startDate)

        // Parse BYDAY
        let daysOfWeek = parseBYDAY(components["BYDAY"])

        // Parse BYMONTHDAY
        let daysOfMonth = components["BYMONTHDAY"]?
            .components(separatedBy: ",")
            .compactMap { Int($0) }
            .compactMap { NSNumber(value: $0) }

        // Parse BYMONTH
        let monthsOfYear = components["BYMONTH"]?
            .components(separatedBy: ",")
            .compactMap { Int($0) }
            .compactMap { NSNumber(value: $0) }

        // Parse BYSETPOS
        let setPositions = components["BYSETPOS"]?
            .components(separatedBy: ",")
            .compactMap { Int($0) }
            .compactMap { NSNumber(value: $0) }

        // Parse BYYEARDAY
        let daysOfYear = components["BYYEARDAY"]?
            .components(separatedBy: ",")
            .compactMap { Int($0) }
            .compactMap { NSNumber(value: $0) }

        // Parse BYWEEKNO
        let weeksOfYear = components["BYWEEKNO"]?
            .components(separatedBy: ",")
            .compactMap { Int($0) }
            .compactMap { NSNumber(value: $0) }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: daysOfMonth,
            monthsOfTheYear: monthsOfYear,
            weeksOfTheYear: weeksOfYear,
            daysOfTheYear: daysOfYear,
            setPositions: setPositions,
            end: end
        )
    }

    // MARK: - Component Parsing

    /// Parse RRULE string into dictionary of components
    private static func parseRRuleComponents(_ rrule: String) -> [String: String] {
        var components: [String: String] = [:]

        // Remove "RRULE:" prefix if present
        var ruleString = rrule
        if ruleString.uppercased().hasPrefix("RRULE:") {
            ruleString = String(ruleString.dropFirst(6))
        }

        // Parse key=value pairs
        for part in ruleString.components(separatedBy: ";") {
            let keyValue = part.components(separatedBy: "=")
            if keyValue.count == 2 {
                components[keyValue[0].uppercased()] = keyValue[1]
            }
        }

        return components
    }

    /// Parse FREQ value
    private static func parseFrequency(_ freq: String) -> EKRecurrenceFrequency? {
        switch freq.uppercased() {
        case "DAILY": return .daily
        case "WEEKLY": return .weekly
        case "MONTHLY": return .monthly
        case "YEARLY": return .yearly
        default: return nil
        }
    }

    /// Parse end condition (COUNT or UNTIL)
    private static func parseEnd(_ components: [String: String], startDate: Date) -> EKRecurrenceEnd? {
        if let count = components["COUNT"], let countValue = Int(count) {
            return EKRecurrenceEnd(occurrenceCount: countValue)
        }

        if let until = components["UNTIL"] {
            if let date = parseUntilDate(until) {
                return EKRecurrenceEnd(end: date)
            }
        }

        return nil // Repeats forever
    }

    /// Parse UNTIL date
    private static func parseUntilDate(_ until: String) -> Date? {
        var value = until
        var timeZone: TimeZone? = nil

        if value.hasSuffix("Z") {
            value = String(value.dropLast())
            timeZone = TimeZone(identifier: "UTC")
        }

        let formats = [
            "yyyyMMdd'T'HHmmss",
            "yyyyMMdd"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone ?? .current

            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    /// Parse BYDAY value
    private static func parseBYDAY(_ byday: String?) -> [EKRecurrenceDayOfWeek]? {
        guard let byday = byday else { return nil }

        var daysOfWeek: [EKRecurrenceDayOfWeek] = []

        for daySpec in byday.components(separatedBy: ",") {
            let trimmed = daySpec.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Parse optional week number (e.g., "2MO" for second Monday)
            var weekNumber = 0
            var dayStr = trimmed

            // Check for leading number (could be negative)
            var numberStr = ""
            for char in trimmed {
                if char.isNumber || char == "-" {
                    numberStr.append(char)
                } else {
                    break
                }
            }

            if !numberStr.isEmpty, let num = Int(numberStr) {
                weekNumber = num
                dayStr = String(trimmed.dropFirst(numberStr.count))
            }

            guard let day = parseDayOfWeek(dayStr) else { continue }

            if weekNumber != 0 {
                daysOfWeek.append(EKRecurrenceDayOfWeek(day, weekNumber: weekNumber))
            } else {
                daysOfWeek.append(EKRecurrenceDayOfWeek(day))
            }
        }

        return daysOfWeek.isEmpty ? nil : daysOfWeek
    }

    /// Parse day abbreviation to EKWeekday
    private static func parseDayOfWeek(_ day: String) -> EKWeekday? {
        switch day.uppercased() {
        case "SU": return .sunday
        case "MO": return .monday
        case "TU": return .tuesday
        case "WE": return .wednesday
        case "TH": return .thursday
        case "FR": return .friday
        case "SA": return .saturday
        default: return nil
        }
    }
}

// MARK: - EKRecurrenceRule to RRULE

extension RecurrenceMapper {
    /// Convert EKRecurrenceRule back to RRULE string
    static func toRRule(_ rule: EKRecurrenceRule) -> String {
        var parts: [String] = []

        // FREQ
        let freq: String
        switch rule.frequency {
        case .daily: freq = "DAILY"
        case .weekly: freq = "WEEKLY"
        case .monthly: freq = "MONTHLY"
        case .yearly: freq = "YEARLY"
        @unknown default: freq = "DAILY"
        }
        parts.append("FREQ=\(freq)")

        // INTERVAL
        if rule.interval > 1 {
            parts.append("INTERVAL=\(rule.interval)")
        }

        // BYDAY
        if let daysOfWeek = rule.daysOfTheWeek, !daysOfWeek.isEmpty {
            let dayStrs = daysOfWeek.map { dayOfWeekToString($0) }
            parts.append("BYDAY=\(dayStrs.joined(separator: ","))")
        }

        // BYMONTHDAY
        if let daysOfMonth = rule.daysOfTheMonth, !daysOfMonth.isEmpty {
            let dayStrs = daysOfMonth.map { String($0.intValue) }
            parts.append("BYMONTHDAY=\(dayStrs.joined(separator: ","))")
        }

        // BYMONTH
        if let months = rule.monthsOfTheYear, !months.isEmpty {
            let monthStrs = months.map { String($0.intValue) }
            parts.append("BYMONTH=\(monthStrs.joined(separator: ","))")
        }

        // BYSETPOS
        if let positions = rule.setPositions, !positions.isEmpty {
            let posStrs = positions.map { String($0.intValue) }
            parts.append("BYSETPOS=\(posStrs.joined(separator: ","))")
        }

        // End condition
        if let end = rule.recurrenceEnd {
            if end.occurrenceCount > 0 {
                parts.append("COUNT=\(end.occurrenceCount)")
            } else if let endDate = end.endDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                formatter.timeZone = TimeZone(identifier: "UTC")
                parts.append("UNTIL=\(formatter.string(from: endDate))")
            }
        }

        return parts.joined(separator: ";")
    }

    private static func dayOfWeekToString(_ day: EKRecurrenceDayOfWeek) -> String {
        let dayStr: String
        switch day.dayOfTheWeek {
        case .sunday: dayStr = "SU"
        case .monday: dayStr = "MO"
        case .tuesday: dayStr = "TU"
        case .wednesday: dayStr = "WE"
        case .thursday: dayStr = "TH"
        case .friday: dayStr = "FR"
        case .saturday: dayStr = "SA"
        @unknown default: dayStr = "MO"
        }

        if day.weekNumber != 0 {
            return "\(day.weekNumber)\(dayStr)"
        }
        return dayStr
    }
}
