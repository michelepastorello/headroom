// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Headroom",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Headroom", targets: ["Headroom"])
    ],
    targets: [
        .executableTarget(
            name: "Headroom",
            path: "Sources/Headroom"
        )
    ]
)
