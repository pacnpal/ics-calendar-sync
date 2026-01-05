import XCTest
@testable import ICSCalendarSyncGUI

final class SyncStatusTests: XCTestCase {

    // MARK: - Icon Tests

    func testIdleIcon() {
        XCTAssertEqual(SyncStatus.idle.icon, "calendar.badge.clock")
    }

    func testSyncingIcon() {
        XCTAssertEqual(SyncStatus.syncing.icon, "arrow.triangle.2.circlepath")
    }

    func testSuccessIcon() {
        XCTAssertEqual(SyncStatus.success.icon, "checkmark.circle")
    }

    func testErrorIcon() {
        XCTAssertEqual(SyncStatus.error("test").icon, "exclamationmark.triangle")
    }

    // MARK: - Equatable Tests

    func testIdleEquality() {
        XCTAssertEqual(SyncStatus.idle, SyncStatus.idle)
    }

    func testSyncingEquality() {
        XCTAssertEqual(SyncStatus.syncing, SyncStatus.syncing)
    }

    func testSuccessEquality() {
        XCTAssertEqual(SyncStatus.success, SyncStatus.success)
    }

    func testErrorEquality() {
        XCTAssertEqual(SyncStatus.error("test"), SyncStatus.error("test"))
    }

    func testErrorInequalityDifferentMessages() {
        XCTAssertNotEqual(SyncStatus.error("error1"), SyncStatus.error("error2"))
    }

    func testDifferentStatusesNotEqual() {
        XCTAssertNotEqual(SyncStatus.idle, SyncStatus.syncing)
        XCTAssertNotEqual(SyncStatus.idle, SyncStatus.success)
        XCTAssertNotEqual(SyncStatus.idle, SyncStatus.error("test"))
        XCTAssertNotEqual(SyncStatus.syncing, SyncStatus.success)
        XCTAssertNotEqual(SyncStatus.syncing, SyncStatus.error("test"))
        XCTAssertNotEqual(SyncStatus.success, SyncStatus.error("test"))
    }

    // MARK: - Error Message Tests

    func testErrorWithEmptyMessage() {
        let status = SyncStatus.error("")
        XCTAssertEqual(status.icon, "exclamationmark.triangle")
    }

    func testErrorWithLongMessage() {
        let longMessage = String(repeating: "a", count: 1000)
        let status = SyncStatus.error(longMessage)
        XCTAssertEqual(status.icon, "exclamationmark.triangle")
    }
}

// MARK: - CalendarInfo Tests

final class CalendarInfoTests: XCTestCase {

    func testInitWithTitle() {
        let info = CalendarInfo(title: "Test Calendar")

        XCTAssertEqual(info.id, "Test Calendar")
        XCTAssertEqual(info.title, "Test Calendar")
        XCTAssertNil(info.color)
        XCTAssertEqual(info.source, "")
    }

    func testIdentifiable() {
        let info = CalendarInfo(title: "Test")
        XCTAssertEqual(info.id, "Test")
    }

    func testHashable() {
        let info1 = CalendarInfo(title: "Calendar 1")
        let info2 = CalendarInfo(title: "Calendar 1")
        let info3 = CalendarInfo(title: "Calendar 2")

        XCTAssertEqual(info1, info2)
        XCTAssertNotEqual(info1, info3)

        var set = Set<CalendarInfo>()
        set.insert(info1)
        set.insert(info2)

        XCTAssertEqual(set.count, 1)
    }
}
