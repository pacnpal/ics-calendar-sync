import XCTest
@testable import ICSCalendarSyncGUI

final class MockLoggerTests: XCTestCase {

    func testDebugLogging() {
        let logger = MockLogger()

        logger.debug("test debug message")

        let messages = logger.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].level, "DEBUG")
        XCTAssertEqual(messages[0].message, "test debug message")
    }

    func testInfoLogging() {
        let logger = MockLogger()

        logger.info("test info message")

        let messages = logger.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].level, "INFO")
        XCTAssertEqual(messages[0].message, "test info message")
    }

    func testWarningLogging() {
        let logger = MockLogger()

        logger.warning("test warning message")

        let messages = logger.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].level, "WARN")
        XCTAssertEqual(messages[0].message, "test warning message")
    }

    func testErrorLogging() {
        let logger = MockLogger()

        logger.error("test error message")

        let messages = logger.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].level, "ERROR")
        XCTAssertEqual(messages[0].message, "test error message")
    }

    func testMultipleMessages() {
        let logger = MockLogger()

        logger.debug("debug")
        logger.info("info")
        logger.warning("warning")
        logger.error("error")

        let messages = logger.messages
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[0].level, "DEBUG")
        XCTAssertEqual(messages[1].level, "INFO")
        XCTAssertEqual(messages[2].level, "WARN")
        XCTAssertEqual(messages[3].level, "ERROR")
    }

    func testClear() {
        let logger = MockLogger()

        logger.info("message 1")
        logger.info("message 2")

        XCTAssertEqual(logger.messages.count, 2)

        logger.clear()

        XCTAssertEqual(logger.messages.count, 0)
    }
}

final class MockFileSystemTests: XCTestCase {

    func testFileExistsInitiallyFalse() {
        let fs = MockFileSystem()

        let exists = fs.fileExists(atPath: "/some/path")

        XCTAssertFalse(exists)
    }

    func testSetFileAndRead() throws {
        let fs = MockFileSystem()

        fs.setFile("/test/file.txt", content: "Hello, World!")

        let exists = fs.fileExists(atPath: "/test/file.txt")
        XCTAssertTrue(exists)

        let data = try fs.readData(atPath: "/test/file.txt")
        let content = String(data: data, encoding: .utf8)
        XCTAssertEqual(content, "Hello, World!")
    }

    func testReadNonexistentFile() {
        let fs = MockFileSystem()

        do {
            _ = try fs.readData(atPath: "/nonexistent")
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }
    }

    func testWriteData() throws {
        let fs = MockFileSystem()

        let data = "Test content".data(using: .utf8)!
        try fs.writeData(data, toPath: "/test/output.txt")

        let exists = fs.fileExists(atPath: "/test/output.txt")
        XCTAssertTrue(exists)

        let content = fs.getFile("/test/output.txt")
        XCTAssertEqual(content, "Test content")
    }

    func testCreateDirectory() throws {
        let fs = MockFileSystem()

        try fs.createDirectory(atPath: "/test/dir")

        let exists = fs.fileExists(atPath: "/test/dir")
        XCTAssertTrue(exists)
    }

    func testGetFileNonexistent() {
        let fs = MockFileSystem()

        let content = fs.getFile("/nonexistent")

        XCTAssertNil(content)
    }

    func testClear() throws {
        let fs = MockFileSystem()

        fs.setFile("/file1.txt", content: "content1")
        fs.setFile("/file2.txt", content: "content2")
        try fs.createDirectory(atPath: "/dir")

        fs.clear()

        XCTAssertFalse(fs.fileExists(atPath: "/file1.txt"))
        XCTAssertFalse(fs.fileExists(atPath: "/file2.txt"))
        XCTAssertFalse(fs.fileExists(atPath: "/dir"))
    }

    func testSetPermissionsNoOp() throws {
        let fs = MockFileSystem()

        fs.setFile("/test.txt", content: "test")

        // Should not throw
        try fs.setPermissions(0o600, atPath: "/test.txt")

        // File should still be accessible
        let content = fs.getFile("/test.txt")
        XCTAssertEqual(content, "test")
    }
}
