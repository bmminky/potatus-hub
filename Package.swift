// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PotatusHub",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PotatusHub", targets: ["PotatusHub"]),
    ],
    targets: [
        .executableTarget(name: "PotatusHub"),
    ]
)
