// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ics-calendar-sync",
    platforms: [
        .macOS(.v13)  // Minimum for modern async/await and EventKit APIs
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.5.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
    ],
    targets: [
        .executableTarget(
            name: "ics-calendar-sync",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .testTarget(
            name: "ics-calendar-syncTests",
            dependencies: ["ics-calendar-sync"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
