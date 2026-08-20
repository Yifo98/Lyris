// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lyris",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Lyris", targets: ["Lyris"]),
    ],
    targets: [
        .executableTarget(
            name: "Lyris",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "LyrisTests",
            dependencies: [.target(name: "Lyris")],
            path: "Tests/LyrisTests"
        ),
    ]
)
