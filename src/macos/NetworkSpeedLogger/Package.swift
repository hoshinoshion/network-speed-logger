// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NetworkSpeedLogger",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NetworkSpeedLogger", targets: ["NetworkSpeedLogger"])
    ],
    targets: [
        .executableTarget(
            name: "NetworkSpeedLogger",
            path: "Sources/NetworkSpeedLogger",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Charts"),
                .linkedFramework("SystemConfiguration")
            ]
        )
    ]
)
