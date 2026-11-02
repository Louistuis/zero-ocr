// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZeroOCR",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ZeroOCR",
            path: "Sources/ZeroOCR",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("CoreImage"),
                .linkedFramework("WebKit"),
            ]
        )
    ]
)
