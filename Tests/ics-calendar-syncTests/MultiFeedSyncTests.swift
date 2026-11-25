import Foundation
import SQLite
import XCTest
@testable import ics_calendar_sync

private actor FixtureCalendar: SyncCalendar {
    var items = [String: CalendarItemMatch]()
    var failRemoval = false

    func seed(_ item: CalendarItemMatch) { items[item.itemID] = item }
    func setFailRemoval(_ value: Bool) { failRemoval = value }
    func requestAccess() async throws {}
    func hasAccess() async -> Bool { true }
    func destination(for config: Configuration, dryRun: Bool) -> String? { config.destination.calendarName }
    func inventory(in calendarID: String, eventDates: [Date]) -> [String: [CalendarItemMatch]] {
        Dictionary(grouping: items.values.filter { $0.calendarID == calendarID }, by: { $0.marker.uid })
    }
    func matches(for uid: String, feed: String, calendar: String, state: SyncedEventRecord?,
                 scanned: [CalendarItemMatch], legacy: SyncStateStore.LegacyIdentifiers?) -> EventMatches {
        EventMatches(candidates: scanned, calendarID: calendar, feed: feed, uid: uid,
                     externalID: state?.calendarItemId, eventID: state?.eventIdentifier)
    }
    func save(_ source: ICSEvent, to item: CalendarItemMatch?, in calendarID: String,
              mapping: EventMapper.MappingConfig) throws -> CalendarItemMatch {
        let id = item?.itemID ?? UUID().uuidString
        let saved = CalendarItemMatch(calendarID: calendarID, itemID: id, externalID: "server-" + id,
            eventID: "event-" + id, marker: .owned(feed: try XCTUnwrap(mapping.feedID), uid: source.uid),
            recurring: source.isRecurring, detached: false)
        items[id] = saved
        return saved
    }
    func remove(_ item: CalendarItemMatch) throws {
        guard !failRemoval, items.removeValue(forKey: item.itemID) != nil else {
            throw CalendarError.eventNotFound(item.itemID)
        }
    }
    func removeDuplicate(_ item: CalendarItemMatch, keeping keeper: CalendarItemMatch) throws {
        XCTAssertNotEqual(item.itemID, keeper.itemID)
        XCTAssertNotNil(items[keeper.itemID])
        try remove(item)
    }
}

final class MultiFeedSyncTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let calendar = FixtureCalendar()

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func config(_ source: String, destination: String = "Shared") -> Configuration {
        var config = Configuration()
        config.source.url = "https://example.test/" + source
        config.destination.calendarName = destination
        config.state.path = directory.appendingPathComponent("custom.db").path
        return config
    }

    private func makeEngine(_ config: Configuration) async throws -> SyncEngine {
        let engine = try SyncEngine(config: config, calendarManager: calendar)
        try await engine.initialize()
        return engine
    }

    private func event(_ uid: String, days: Int = 0) -> ICSEvent {
        let date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(days) * 86400)
        return .minimal(uid: uid, summary: "Same title", startDate: date, endDate: date.addingTimeInterval(3600))
    }

    func testThreeFeedsMoveRecoverAndDeleteIndependently() async throws {
        let a = try await makeEngine(config("a"))
        let b = try await makeEngine(config("b"))
        let c = try await makeEngine(config("c", destination: "Private"))
        let initial = try await a.reconcile([event("same"), event("old")])
        XCTAssertEqual(initial.created, 2)
        for engine in [b, c] {
            let first = try await engine.reconcile([event("same")])
            XCTAssertEqual(first.created, 1)
        }
        let items = await calendar.items
        let owner = config("a").feedState.id
        let original = try XCTUnwrap(items.values.first { $0.marker == .owned(feed: owner, uid: "same") })
        await calendar.seed(CalendarItemMatch(calendarID: "Shared", itemID: "duplicate", externalID: "copy",
            eventID: "copy", marker: original.marker, recurring: false, detached: false))

        let moved = try await a.reconcile([event("same", days: 14), event("new")])
        XCTAssertTrue(moved.isSuccess)
        XCTAssertEqual(moved.updated, 1)
        XCTAssertEqual(moved.created, 1)
        XCTAssertEqual(moved.deleted, 2) // One owned duplicate and one tracked orphan.
        let after = await calendar.items
        XCTAssertNotNil(after[original.itemID])
        XCTAssertNil(after["duplicate"])
        XCTAssertEqual(after.count, 4)
        for engine in [b, c] {
            let next = try await engine.reconcile([event("same")])
            XCTAssertEqual(next.unchanged, 1)
            XCTAssertEqual(next.deleted, 0)
        }

        try await a.resetState()
        let recovered = try await a.reconcile([event("same", days: 21), event("new")])
        XCTAssertEqual(recovered.created, 0)
        XCTAssertEqual(recovered.updated, 2)
    }

    func testMissingLookupAndFailedRemoveRetainRowUntilRetry() async throws {
        let engine = try await makeEngine(config("a"))
        _ = try await engine.reconcile([event("keep"), event("orphan")])
        let items = await calendar.items
        let orphan = try XCTUnwrap(items.values.first { $0.marker.uid == "orphan" })
        try await calendar.remove(orphan)
        let missing = try await engine.reconcile([event("keep")])
        XCTAssertTrue(missing.hasErrors)
        XCTAssertEqual(missing.deleted, 0)
        await calendar.seed(orphan)
        await calendar.setFailRemoval(true)
        let failed = try await engine.reconcile([event("keep")])
        XCTAssertTrue(failed.hasErrors)
        XCTAssertEqual(failed.deleted, 0)
        let retained = try await engine.getStatus()
        XCTAssertEqual(retained.eventCount, 2)
        await calendar.setFailRemoval(false)
        let retried = try await engine.reconcile([event("keep")])
        XCTAssertEqual(retried.deleted, 1)
        let final = try await engine.getStatus()
        XCTAssertEqual(final.eventCount, 1)
    }

    func testLegacyAndDeletionGuards() async throws {
        let a = config("a")
        let connection = try Connection(a.state.path)
        try connection.execute("""
            CREATE TABLE synced_events(source_uid TEXT PRIMARY KEY, calendar_item_id TEXT, event_identifier TEXT);
            INSERT INTO synced_events VALUES ('old', 'external', 'local');
            """)
        let engine = try await makeEngine(a)
        let old = CalendarItemMatch(calendarID: "Shared", itemID: "legacy", externalID: "external",
            eventID: "local", marker: .legacy(uid: "old"), recurring: false, detached: false)
        await calendar.seed(old)
        let legacy = try await engine.reconcile([event("old")])
        XCTAssertTrue(legacy.hasErrors)
        XCTAssertEqual(legacy.created, 0)
        XCTAssertEqual(legacy.deleted, 0)
        let events = (0..<12).map { event("id-\($0)") }
        _ = try await engine.reconcile(events)
        let empty = try await engine.reconcile([])
        let replaced = try await engine.reconcile([event("replacement")])
        let mass = try await engine.reconcile([events[0]])
        XCTAssertEqual(empty.deleted, 0)
        XCTAssertEqual(replaced.deleted, 0)
        XCTAssertEqual(mass.deleted, 0)
        let preview = try await engine.reconcile(Array(events.dropLast()), dryRun: true)
        XCTAssertEqual(preview.deleted, 2)
        var disabled = a
        disabled.sync.deleteOrphans = false
        let safe = try await makeEngine(disabled)
        let kept = try await safe.reconcile(Array(events.dropLast()))
        XCTAssertEqual(kept.deleted, 0)
        let beforeReset = try await safe.getStatus()
        XCTAssertEqual(beforeReset.eventCount, 13)
        try await safe.resetState()
        XCTAssertEqual(try connection.scalar("SELECT COUNT(*) FROM synced_events") as? Int64, 1)
        let surviving = await calendar.items
        XCTAssertEqual(surviving["legacy"]?.marker, old.marker)
    }

    func testRecurringOccurrencesAndCollidingExternalIDs() {
        func match(_ id: String, _ marker: EventMarker, calendar: String = "Shared",
                   recurring: Bool = false, detached: Bool = false) -> CalendarItemMatch {
            CalendarItemMatch(calendarID: calendar, itemID: id, externalID: "server", eventID: id,
                              marker: marker, recurring: recurring, detached: detached)
        }
        let owner = EventMarker.owned(feed: "a", uid: "same")
        let series = match("series", owner, recurring: true)
        let others = [match("foreign", .owned(feed: "b", uid: "same")), match("elsewhere", owner, calendar: "Work")]
        let result = EventMatches(candidates: [series, series] + others, calendarID: "Shared", feed: "a",
                                  uid: "same", externalID: "server", eventID: "foreign")
        XCTAssertEqual(result.keeper?.itemID, "series")
        XCTAssertTrue(result.duplicates.isEmpty)
        XCTAssertFalse(result.ambiguous)
        let ambiguous = EventMatches(candidates: [series, match("exception", owner, detached: true)],
            calendarID: "Shared", feed: "a", uid: "same", externalID: nil, eventID: nil)
        XCTAssertTrue(ambiguous.ambiguous)
        XCTAssertTrue(ambiguous.duplicates.isEmpty)
        let collision = EventMatches(candidates: [match("first", owner), match("second", owner)] + others,
            calendarID: "Shared", feed: "a", uid: "same", externalID: "server", eventID: "second")
        XCTAssertEqual(collision.keeper?.itemID, "second")
        XCTAssertEqual(collision.duplicates.map(\.itemID), ["first"])
    }

    func testCombinedDuplicateCountHonorsMassDeletionGuard() async throws {
        let feed = config("a")
        let engine = try await makeEngine(feed)
        _ = try await engine.reconcile([event("same")])
        for index in 0..<12 {
            let copy = CalendarItemMatch(calendarID: "Shared", itemID: "copy-\(index)", externalID: nil,
                eventID: nil, marker: .owned(feed: feed.feedState.id, uid: "same"), recurring: false, detached: false)
            await calendar.seed(copy)
        }
        let result = try await engine.reconcile([event("same")])
        XCTAssertEqual(result.deleted, 0)
        let items = await calendar.items
        XCTAssertEqual(items.count, 13)
    }

    func testQueryHorizonAndMarkerRoundTrip() {
        let now = Date()
        let start = now.addingTimeInterval(-5 * 365 * 86400)
        let end = now.addingTimeInterval(5 * 365 * 86400)
        let chunks = CalendarQuery.chunks(from: start, to: end)
        XCTAssertEqual(chunks.first?.start, start)
        XCTAssertEqual(chunks.last?.end, end)
        XCTAssertTrue(chunks.allSatisfy { $0.duration > 0 && $0.duration < 4 * 365 * 86400 })
        for (first, second) in zip(chunks, chunks.dropFirst()) { XCTAssertEqual(first.end, second.start) }
        XCTAssertTrue(CalendarQuery.chunks(from: now, to: now).isEmpty)
        let marker = EventMarker.owned(feed: "a", uid: "café]:calendar")
        XCTAssertEqual(EventMarker(notes: "[ICS-SYNC-UID:wrong]\n\n" + marker.line), marker)
        let legacy = EventMarker.legacy(uid: "old")
        XCTAssertEqual(EventMarker(notes: marker.line + "\n" + legacy.line + "\n---\nSynced from: example"), legacy)
    }

    func testOverlappingChunksPreserveSeparateOccurrences() {
        struct Occurrence: Hashable {
            let item: String
            let date: Date
        }
        let start = Date(timeIntervalSince1970: 0)
        let year: TimeInterval = 365 * 86400
        let seam = start.addingTimeInterval(3 * year)
        let first = Occurrence(item: "series", date: seam)
        let second = Occurrence(item: "series", date: start.addingTimeInterval(5 * year))
        let events = CalendarQuery.events(from: start, to: start.addingTimeInterval(10 * year), key: { $0 }) { chunk in
            XCTAssertLessThan(chunk.duration, 4 * year)
            return [first, second].filter { chunk.start <= $0.date && $0.date <= chunk.end }
        }
        XCTAssertEqual(events, [first, second])
    }

    func testScopedHistoryAndMetadataInAnExplicitlySharedFile() async throws {
        let a = SyncStateStore(config: config("a"))
        let b = SyncStateStore(config: config("b"))
        try await a.initialize()
        try await b.initialize()
        try await a.setMetadata(key: "etag", value: "a-etag")
        try await b.setMetadata(key: "etag", value: "b-etag")
        let aRun = try await a.recordSyncStart()
        let bRun = try await b.recordSyncStart()
        try await a.recordSyncComplete(id: aRun, status: .success, created: 2, updated: 0, deleted: 0, unchanged: 0)
        try await b.recordSyncComplete(id: bRun, status: .success, created: 4, updated: 0, deleted: 0, unchanged: 0)
        let history = try await a.getRecentHistory()
        XCTAssertEqual(history.map(\.eventsCreated), [2])
        try await a.reset()
        let remaining = try await b.getRecentHistory()
        let metadata = try await b.getMetadata(key: "etag")
        XCTAssertEqual(remaining.map(\.eventsCreated), [4])
        XCTAssertEqual(metadata, "b-etag")
    }

    func testRecurringOverrideCannotReplaceMaster() async throws {
        var master = event("weekly")
        master.recurrenceRule = "FREQ=WEEKLY"
        var override = event("weekly", days: 7)
        override.isRecurrenceOverride = true
        override.sequence = 9
        XCTAssertEqual(SyncEngine.masters(in: [master, override]).first?.recurrenceRule, "FREQ=WEEKLY")
        let engine = try await makeEngine(config("a"))
        _ = try await engine.reconcile([master])
        let overrideOnly = try await engine.reconcile([override, event("other")])
        XCTAssertEqual(overrideOnly.deleted, 0)
    }
}
