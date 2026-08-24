// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChromaDock",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChromaDockCore", targets: ["ChromaDockCore"])
    ],
    targets: [
        .target(
            name: "ChromaDockCore",
            path: "Sources/ChromaDock",
            exclude: ["main.swift", "App.swift", "ContentView.swift", "ContactInterestView.swift"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "ChromaDockCoreTests",
            dependencies: ["ChromaDockCore"],
            path: "Tests/ChromaDockCoreTests"
        )
    ]
)
