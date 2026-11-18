// swift-tools-version:5.9
import PackageDescription

// Swift 5 language mode (tools-version 5.9) keeps this small AppKit app free of
// Swift 6 strict-concurrency noise. AppKit/SwiftUI/ServiceManagement are linked by `import`.
let package = Package(
    name: "WinSwitch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WinSwitch",
            path: "Sources/WinSwitch"
        )
    ]
)
