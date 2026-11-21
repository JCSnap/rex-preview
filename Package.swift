// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "rex-preview",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "rex-preview", targets: ["RexPreview"]),
    ],
    targets: [
        .executableTarget(
            name: "RexPreview",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("AVKit"),
                .linkedFramework("QuickLookUI"),
            ]
        ),
    ]
)
