import Darwin
import Foundation
import XCTest
@testable import ics_calendar_sync

final class LoggerTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testClearKeepsOpenLoggersOnCurrentFiles() throws {
        let dir = try temporaryDirectory()
        let logger = Logger(logDirectory: dir)
        logger.progress("before")
        logger.failure("before")
        try LogsCommand.clearLogs(in: dir.path)
        logger.progress("after")
        logger.failure("after")

        XCTAssertEqual(try contents(of: "stdout.log", in: dir), "  → after\n")
        XCTAssertEqual(try contents(of: "stderr.log", in: dir), "  ✗ after\n")
    }

    func testOneUnavailableLogKeepsItsConsoleAndTheOtherLog() throws {
        let dir = try temporaryDirectory()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("stderr.log"), withIntermediateDirectories: false)
        let console = try XCTUnwrap(fopen(dir.appendingPathComponent("console").path, "w"))
        defer { fclose(console) }

        do {
            let logger = Logger(logDirectory: dir, standardOutput: console, standardError: console)
            logger.progress("normal")
            logger.failure("error")
        }
        XCTAssertGreaterThanOrEqual(fcntl(fileno(console), F_GETFD), 0)
        XCTAssertEqual(try contents(of: "stdout.log", in: dir), "  → normal\n")
        XCTAssertEqual(try contents(of: "console", in: dir), "  → normal\n  ✗ error\n")
    }

    func testCombinedRedirectionAppendsToEachDistinctLogOnce() throws {
        let dir = try temporaryDirectory()
        let out = dir.appendingPathComponent("stdout.log")
        try Data("prefix\n".utf8).write(to: out)
        let console = try XCTUnwrap(fopen(out.path, "r+"))
        defer { fclose(console) }

        do {
            let logger = Logger(logDirectory: dir, standardOutput: console, standardError: console)
            logger.progress("normal")
            logger.failure("error")
        }
        XCTAssertEqual(try contents(of: "stdout.log", in: dir), "prefix\n  → normal\n  ✗ error\n")
        XCTAssertEqual(try contents(of: "stderr.log", in: dir), "  ✗ error\n")
        XCTAssertEqual(ftell(console), 0)
    }

    private func contents(of name: String, in dir: URL) throws -> String {
        try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    func testConcurrentDaemonCLIAndGUIWriters() throws {
        let dir = try temporaryDirectory()
        let executable = dir.appendingPathComponent("writer")
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = tests.deletingLastPathComponent().deletingLastPathComponent()
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        #if arch(arm64)
        let target = "arm64-apple-macosx14.0"
        #else
        let target = "x86_64-apple-macosx14.0"
        #endif
        compiler.arguments = [
            "swiftc", "-target", target,
            root.appendingPathComponent("Sources/ics-calendar-sync/Utilities/Logger.swift").path,
            tests.appendingPathComponent("Fixtures/LogWriter/main.swift").path, "-o", executable.path
        ]
        try compiler.run()
        compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        guard compiler.terminationStatus == 0 else { return }

        let out = dir.appendingPathComponent("stdout.log")
        let err = dir.appendingPathComponent("stderr.log")
        try Data("existing\n".utf8).write(to: out)
        try Data("existing\n".utf8).write(to: err)
        let alias = dir.appendingPathComponent("stdout-alias")
        try FileManager.default.linkItem(at: out, to: alias)

        let names = ["daemon", "cli", "gui"]
        let guiOut = Pipe()
        let guiErr = Pipe()
        var gates = [Pipe]()
        var children = [Process]()
        var finished = [XCTestExpectation]()
        defer {
            for child in children where child.isRunning { child.terminate() }
        }
        for name in names {
            let child = Process()
            child.executableURL = executable
            child.arguments = [dir.path, name]
            let gate = Pipe()
            child.standardInput = gate
            gates.append(gate)
            switch name {
            case "daemon":
                // Deliberately positioned at byte zero, without O_APPEND.
                child.standardOutput = try FileHandle(forWritingTo: alias)
                child.standardError = try FileHandle(forWritingTo: err)
            case "cli":
                child.standardOutput = FileHandle.nullDevice
                child.standardError = FileHandle.nullDevice
            default:
                child.standardOutput = guiOut
                child.standardError = guiErr
            }
            let done = XCTestExpectation(description: name)
            child.terminationHandler = { _ in done.fulfill() }
            try child.run()
            children.append(child)
            finished.append(done)
        }

        func ready() -> Bool {
            names.allSatisfy { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0 + ".ready").path) }
        }
        let deadline = Date(timeIntervalSinceNow: 15)
        while !ready() && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        guard ready() else { return XCTFail("Log writers did not open their files") }

        // Force every seek-once handle to be stale before any worker writes.
        for url in [out, err] {
            let file = try FileHandle(forWritingTo: url)
            try file.seekToEnd()
            try file.write(contentsOf: Data("sentinel\n".utf8))
            try file.close()
        }
        for gate in gates {
            try gate.fileHandleForWriting.write(contentsOf: Data("start\n".utf8))
            try gate.fileHandleForWriting.close()
        }
        guard XCTWaiter.wait(for: finished, timeout: 20) == .completed else {
            return XCTFail("Log writers did not finish")
        }
        XCTAssertTrue(children.allSatisfy { $0.terminationStatus == 0 })

        for (url, pipe, isError) in [(out, guiOut, false), (err, guiErr, true)] {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.hasPrefix("existing\nsentinel\n"))
            XCTAssertFalse(text.contains("\u{1B}"))
            XCTAssertTrue(text.hasSuffix("\n"))
            let lines = text.components(separatedBy: "\n").dropFirst(2).dropLast()
            let console = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertTrue(console.contains("\u{1B}"))
            let plainConsole = console.replacingOccurrences(of: "\u{1B}\\[[0-9]+m", with: "", options: .regularExpression)
            let guiLines = plainConsole.components(separatedBy: "\n").dropLast()
            try checkRecords(Array(lines), writers: names, isError: isError)
            try checkRecords(Array(guiLines), writers: ["gui"], isError: isError)
        }
    }

    private func checkRecords(_ lines: [String], writers: [String], isError: Bool) throws {
        var expected = [String]()
        if writers.contains("daemon") { expected.append(isError ? "direct stderr" : "direct stdout") }
        for writer in writers {
            expected += (0..<8).map { "\(writer)-\($0)" }
            if isError {
                expected.append("  ✗ " + writer)
            } else {
                expected += ["INFO info-" + writer, "WARN warn-" + writer, String(repeating: "-", count: 60),
                             "  → " + writer, "  ✓ " + writer]
            }
        }
        let actual = try lines.map { line -> String in
            if line.hasPrefix("{") {
                let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
                XCTAssertNotNil(json["timestamp"] as? String)
                XCTAssertEqual(json["level"] as? String, isError ? "error" : "debug")
                let message = try XCTUnwrap(json["message"] as? String)
                if !isError {
                    XCTAssertEqual(json["file"] as? String, "Worker.swift")
                    XCTAssertEqual(json["function"] as? String, "sync()")
                    XCTAssertEqual(json["line"] as? Int, message.split(separator: "-").last.flatMap { Int($0) })
                }
                return message
            }
            if line.hasPrefix("["), let end = line.range(of: "] ") { return String(line[end.upperBound...]) }
            return line
        }
        XCTAssertEqual(actual.sorted(), expected.sorted())
    }
}
