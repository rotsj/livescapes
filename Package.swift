// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveScapes",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LiveScapes", targets: ["LiveScapes"])
    ],
    targets: [
        .executableTarget(
            name: "LiveScapes",
            path: "Sources/LiveScapes"
        )
    ]
)
