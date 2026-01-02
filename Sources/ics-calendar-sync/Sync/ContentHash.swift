import Foundation
import CryptoKit

// MARK: - Content Hash

/// Utility for calculating stable content hashes for change detection
enum ContentHash {
    /// Calculate a stable hash of event content for change detection.
    /// Includes content fields that matter for sync, excludes metadata that changes on sync.
    static func calculate(for event: ICSEvent) -> String {
        var hasher = SHA256()

        // Include stable content fields only
        // Order matters for hash stability

        // Core fields
        addToHash(&hasher, event.uid)
        addToHash(&hasher, event.summary)
        addToHash(&hasher, event.description)
        addToHash(&hasher, event.location)
        addToHash(&hasher, event.url?.absoluteString)

        // Date/time fields
        addToHash(&hasher, formatDate(event.startDate))
        addToHash(&hasher, formatDate(event.endDate))
        addToHash(&hasher, event.isAllDay ? "allday" : "timed")
        addToHash(&hasher, event.timeZone?.identifier)

        // Recurrence
        addToHash(&hasher, event.recurrenceRule)
        for date in event.exceptionDates.sorted() {
            addToHash(&hasher, formatDate(date))
        }
        for date in event.recurrenceDates.sorted() {
            addToHash(&hasher, formatDate(date))
        }

        // Status
        addToHash(&hasher, event.status?.rawValue)
        addToHash(&hasher, event.transparency?.rawValue)
        addToHash(&hasher, event.priority.map { String($0) })

        // Alarms
        for alarm in event.alarms.sorted(by: { $0.trigger < $1.trigger }) {
            addToHash(&hasher, alarm.action.rawValue)
            addToHash(&hasher, String(alarm.trigger))
            addToHash(&hasher, alarm.description)
        }

        // Categories
        for category in event.categories.sorted() {
            addToHash(&hasher, category)
        }

        // Organizer
        addToHash(&hasher, event.organizer?.email)
        addToHash(&hasher, event.organizer?.name)

        // Attendees (sorted by email for stability)
        for attendee in event.attendees.sorted(by: { ($0.email ?? "") < ($1.email ?? "") }) {
            addToHash(&hasher, attendee.email)
            addToHash(&hasher, attendee.name)
            addToHash(&hasher, attendee.role?.rawValue)
            addToHash(&hasher, attendee.participationStatus?.rawValue)
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Calculate hash from raw ICS data
    static func calculateFromRaw(_ icsData: String) -> String {
        // Normalize line endings and whitespace
        let normalized = icsData
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var hasher = SHA256()
        hasher.update(data: Data(normalized.utf8))
        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private Helpers

    private static func addToHash(_ hasher: inout SHA256, _ value: String?) {
        if let value = value {
            hasher.update(data: Data(value.utf8))
        }
        // Add separator byte to prevent concatenation issues
        hasher.update(data: Data([0]))
    }

    private static func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

// MARK: - Quick Hash

extension ContentHash {
    /// Generate a short hash suitable for display
    static func shortHash(for event: ICSEvent) -> String {
        let full = calculate(for: event)
        return String(full.prefix(8))
    }

    /// Check if two events have the same content
    static func areEqual(_ event1: ICSEvent, _ event2: ICSEvent) -> Bool {
        calculate(for: event1) == calculate(for: event2)
    }
}
