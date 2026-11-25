import Foundation

enum EventMarker: Equatable {
    case owned(feed: String, uid: String)
    case legacy(uid: String)
    case unmarked(uid: String)

    var uid: String {
        switch self {
        case let .owned(_, uid), let .legacy(uid), let .unmarked(uid): return uid
        }
    }

    var line: String {
        switch self {
        case let .owned(feed, uid):
            return "[ICS-SYNC-V2:\(feed):\(Data(uid.utf8).base64EncodedString())]"
        case .unmarked: return ""
        case let .legacy(uid):
            return "[ICS-SYNC-UID:\(uid)]"
        }
    }

    init?(notes: String?) {
        guard let notes else { return nil }
        // Use the trailer written by the mapper. Descriptions can themselves contain marker text.
        var lines = notes.split(whereSeparator: \.isNewline)
        if lines.last?.hasPrefix("Synced from: ") == true, lines.dropLast().last == "---" {
            lines.removeLast(2)
        }
        guard let line = lines.last, line.hasSuffix("]") else { return nil }
        if line.hasPrefix("[ICS-SYNC-V2:") {
            let parts = line.dropFirst("[ICS-SYNC-V2:".count).dropLast().split(separator: ":")
            guard parts.count == 2, let data = Data(base64Encoded: String(parts[1])),
                  let uid = String(data: data, encoding: .utf8), !uid.isEmpty else { return nil }
            self = .owned(feed: String(parts[0]), uid: uid)
        } else if line.hasPrefix("[ICS-SYNC-UID:") {
            self = .legacy(uid: String(line.dropFirst("[ICS-SYNC-UID:".count).dropLast()))
        } else {
            return nil
        }
    }
}

/// Calendar item IDs identify series. Occurrences of a series can have different dates.
struct CalendarItemMatch {
    let calendarID: String
    let itemID: String
    let externalID: String?
    let eventID: String?
    let marker: EventMarker
    let recurring: Bool
    let detached: Bool
}

struct EventMatches {
    let keeper: CalendarItemMatch?
    let duplicates: [CalendarItemMatch]
    let legacy: [CalendarItemMatch]
    let ambiguous: Bool

    init(candidates: [CalendarItemMatch], calendarID: String, feed: String, uid: String,
         externalID: String?, eventID: String?) {
        let local = candidates.filter { $0.calendarID == calendarID && !$0.itemID.isEmpty }
        let owned = local.filter { $0.marker == .owned(feed: feed, uid: uid) }
        let series = owned.contains { $0.recurring || $0.detached }
        var seen = Set<String>()
        let items = owned.reversed().filter { !$0.detached && seen.insert($0.itemID).inserted }
            .sorted { $0.itemID < $1.itemID }
        let external = items.filter { externalID?.isEmpty == false && $0.externalID == externalID }
        let serverMatch = external.count == 1 ? external.first : nil
        let localIDs = items.filter { eventID?.isEmpty == false && $0.eventID == eventID }
        let localMatch = localIDs.count == 1 ? localIDs.first : nil
        let tracked = localMatch ?? serverMatch
        let conflictingIDs = localMatch != nil && serverMatch != nil && localMatch?.itemID != serverMatch?.itemID
        let hadRecord = externalID != nil || eventID != nil
        ambiguous = conflictingIDs || (hadRecord && items.count > 1 && tracked == nil)
            || (series && (Set(owned.map(\.itemID)).count > 1 || items.isEmpty))
        let chosen = tracked ?? items.first
        keeper = ambiguous ? nil : chosen
        // When state was lost, a deterministic owned item becomes canonical after a successful save.
        duplicates = (series || ambiguous) ? [] : items.filter { $0.itemID != chosen?.itemID }
        seen.removeAll()
        legacy = local.filter {
            ($0.marker == .legacy(uid: uid) || $0.marker == .unmarked(uid: uid)) && seen.insert($0.itemID).inserted
        }
    }
}

enum CalendarQuery {
    /// An item can overlap adjacent predicates. Keep each occurrence once across their union.
    static func events<Item, Key: Hashable>(from start: Date, to end: Date,
                                            key: (Item) -> Key, fetch: (DateInterval) -> [Item]) -> [Item] {
        var seen = Set<Key>()
        var result = [Item]()
        for chunk in chunks(from: start, to: end) {
            result += fetch(chunk).filter { seen.insert(key($0)).inserted }
        }
        return result
    }

    static func chunks(from start: Date, to end: Date) -> [DateInterval] {
        var chunks: [DateInterval] = []
        var cursor = start
        while cursor < end {
            // Leave margin below EventKit's four-calendar-year predicate limit.
            let next = min(cursor.addingTimeInterval(3 * 365 * 86400), end)
            chunks.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        return chunks
    }
}
