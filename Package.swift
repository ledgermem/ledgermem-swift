// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mnemo",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "Mnemo", targets: ["Mnemo"]),
    ],
    targets: [
        .target(
            name: "Mnemo",
            path: "Sources/Mnemo"
        ),
        .testTarget(
            name: "MnemoTests",
            dependencies: ["Mnemo"],
            path: "Tests/MnemoTests"
        ),
    ]
)
