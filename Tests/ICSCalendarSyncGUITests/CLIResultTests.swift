import XCTest
@testable import ICSCalendarSyncGUI

final class CLIResultTests: XCTestCase {

    // MARK: - Static Factory Tests

    func testSuccessFactory() {
        let result = CLIResult.success

        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testFailureFactory() {
        let result = CLIResult.failure("Something went wrong")

        XCTAssertEqual(result.output, "Something went wrong")
        XCTAssertEqual(result.exitCode, 1)
    }

    func testFailureFactoryEmptyMessage() {
        let result = CLIResult.failure("")

        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.exitCode, 1)
    }

    // MARK: - Direct Init Tests

    func testDirectInit() {
        let result = CLIResult(output: "test output", exitCode: 42)

        XCTAssertEqual(result.output, "test output")
        XCTAssertEqual(result.exitCode, 42)
    }

    // MARK: - Equatable Tests

    func testEquatable() {
        let result1 = CLIResult(output: "test", exitCode: 0)
        let result2 = CLIResult(output: "test", exitCode: 0)
        let result3 = CLIResult(output: "different", exitCode: 0)
        let result4 = CLIResult(output: "test", exitCode: 1)

        XCTAssertEqual(result1, result2)
        XCTAssertNotEqual(result1, result3)
        XCTAssertNotEqual(result1, result4)
    }
}

// MARK: - MockCLIRunner Tests

final class MockCLIRunnerTests: XCTestCase {

    func testDefaultResponse() async {
        let mock = MockCLIRunner()

        let result = await mock.run(arguments: ["unknown"])

        XCTAssertEqual(result, .success)
    }

    func testSetResponse() async {
        let mock = MockCLIRunner()
        await mock.setResponse(for: "sync", result: .failure("Sync failed"))

        let result = await mock.run(arguments: ["sync"])

        XCTAssertEqual(result.output, "Sync failed")
        XCTAssertEqual(result.exitCode, 1)
    }

    func testCallHistory() async {
        let mock = MockCLIRunner()

        _ = await mock.run(arguments: ["sync"])
        _ = await mock.run(arguments: ["status", "--json"])
        _ = await mock.run(arguments: ["start"])

        let history = await mock.getCallHistory()

        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0], ["sync"])
        XCTAssertEqual(history[1], ["status", "--json"])
        XCTAssertEqual(history[2], ["start"])
    }

    func testClear() async {
        let mock = MockCLIRunner()
        await mock.setResponse(for: "sync", result: .failure("error"))
        _ = await mock.run(arguments: ["sync"])

        await mock.clear()

        let history = await mock.getCallHistory()
        XCTAssertTrue(history.isEmpty)

        let result = await mock.run(arguments: ["sync"])
        XCTAssertEqual(result, .success) // Default after clear
    }
}
