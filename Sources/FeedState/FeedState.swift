import CryptoKit
import Foundation
import SQLite

/// The same source and destination identify a feed in the GUI, daemon and CLI.
public struct FeedState: Hashable, Sendable {
    public let id: String
    public static let owner = SQLite.Expression<String>("feed_id")

    public init(source: String, calendar: String) {
        // A byte length makes the pair unambiguous even with punctuation in either field.
        let key = "\(source.utf8.count):\(source)\(calendar)"
        id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static let eventTable = Table("feed_events")
    public static let historyTable = Table("feed_history")
    public static let metadataTable = Table("feed_metadata")

    public var events: Table { Self.eventTable.filter(Self.owner == id) }
    public var history: Table { Self.historyTable.filter(Self.owner == id) }
    public var metadata: Table { Self.metadataTable.filter(Self.owner == id) }

    public static func initialize(_ db: Connection) throws {
        // v2.1 rows have no feed identity. Leave all three original tables available for inspection.
        try db.transaction {
            try db.execute("""
                CREATE TABLE IF NOT EXISTS feed_events (
                    feed_id TEXT NOT NULL, source_uid TEXT NOT NULL,
                    calendar_item_id TEXT NOT NULL, event_identifier TEXT,
                    content_hash TEXT NOT NULL, sequence INTEGER NOT NULL DEFAULT 0,
                    last_modified TEXT, synced_at TEXT NOT NULL, ics_data TEXT NOT NULL,
                    PRIMARY KEY (feed_id, source_uid)
                );
                CREATE TABLE IF NOT EXISTS feed_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, feed_id TEXT NOT NULL,
                    started_at TEXT NOT NULL, completed_at TEXT, status TEXT NOT NULL,
                    events_created INTEGER NOT NULL DEFAULT 0, events_updated INTEGER NOT NULL DEFAULT 0,
                    events_deleted INTEGER NOT NULL DEFAULT 0, events_unchanged INTEGER NOT NULL DEFAULT 0,
                    error_message TEXT
                );
                CREATE INDEX IF NOT EXISTS feed_history_by_feed ON feed_history(feed_id, id);
                CREATE TABLE IF NOT EXISTS feed_metadata (
                    feed_id TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, updated_at TEXT NOT NULL,
                    PRIMARY KEY (feed_id, key)
                );
                """)
        }
    }

    /// Call inside the caller's transaction (the GUI may reset several feeds together).
    public func reset(in db: Connection) throws {
        try db.run(events.delete())
        try db.run(history.delete())
        try db.run(metadata.delete())
    }
}

public extension String {
    /// Expand environment variables in the form ${VAR_NAME}
    var expandingEnvironmentVariables: String {
        var result = self
        let pattern = "\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return self
        }

        let matches = regex.matches(in: self, options: [], range: NSRange(self.startIndex..., in: self))

        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: self),
                  let varNameRange = Range(match.range(at: 1), in: self) else {
                continue
            }

            let varName = String(self[varNameRange])
            let value = ProcessInfo.processInfo.environment[varName] ?? ""
            result.replaceSubrange(fullRange, with: value)
        }

        return result
    }
}
