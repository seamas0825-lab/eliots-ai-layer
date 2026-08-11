// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SelectAI",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SelectAI", targets: ["SelectAI"])
    ],
    targets: [
        .executableTarget(
            name: "SelectAI",
            path: "Sources/SelectAI",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
