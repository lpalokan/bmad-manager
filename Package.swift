// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "bmad-manager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "bmad-manager",
            path: "Sources/BmadManager"
        )
    ]
)
