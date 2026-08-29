// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MikroTikDashboard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MikroTikDashboard", targets: ["MikroTikDashboard"]),
        .library(name: "MikroTikKit", targets: ["MikroTikKit"]),
    ],
    targets: [
        // Shared model + networking layer. Compiled into the app, the widget
        // extension and the test bundle.
        .target(name: "MikroTikKit"),

        // The SwiftUI dashboard application.
        .executableTarget(
            name: "MikroTikDashboard",
            dependencies: ["MikroTikKit"]
        ),

        // WidgetKit sources. SwiftPM cannot package an .appex, so this target
        // exists only to type-check the widget code. The real extension is
        // produced by scripts/build-app.sh or MikroTikDashboard.xcodeproj.
        .target(
            name: "MikroTikWidgetSources",
            dependencies: ["MikroTikKit"],
            path: "Sources/MikroTikWidget"
        ),

        // XCTest and swift-testing both live inside Xcode.app, so a Command
        // Line Tools toolchain cannot build a .testTarget. The suite is an
        // executable instead: `swift run MikroTikKitTests`.
        .executableTarget(
            name: "MikroTikKitTests",
            dependencies: ["MikroTikKit"],
            path: "Tests/MikroTikKitTests"
        ),
    ]
)
