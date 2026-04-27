// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LedgerMem",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "LedgerMem", targets: ["LedgerMem"]),
    ],
    targets: [
        .target(
            name: "LedgerMem",
            path: "Sources/LedgerMem"
        ),
        .testTarget(
            name: "LedgerMemTests",
            dependencies: ["LedgerMem"],
            path: "Tests/LedgerMemTests"
        ),
    ]
)
