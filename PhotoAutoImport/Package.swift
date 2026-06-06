// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PhotoAutoImport",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "PhotoAutoImport",
            path: "Sources/PhotoAutoImport"
        )
    ]
)
