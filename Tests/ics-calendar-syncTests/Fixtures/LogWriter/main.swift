import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let name = CommandLine.arguments[2]
let logger = Logger(logDirectory: directory)
logger.useColors = true

// Both log handles are open before the parent appends a sentinel and releases stdin.
try Data().write(to: directory.appendingPathComponent(name + ".ready"))
guard readLine() == "start" else { exit(1) }

logger.configure(level: .debug, format: .json, quiet: false)
for n in 0..<8 {
    logger.debug("\(name)-\(n)", file: "Worker.swift", function: "sync()", line: n)
    logger.error("\(name)-\(n)")
}

logger.format = .text
logger.info("info-\(name)")
logger.warning("warn-\(name)")
logger.separator()
logger.progress(name)
logger.success(name)
logger.failure(name)

// Exercise direct stdio too, as used by sync summaries and CLI diagnostics.
if name == "daemon" {
    print("direct stdout")
    fputs("direct stderr\n", stderr)
}
