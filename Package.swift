// swift-tools-version:6.2
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localFrameworkPath = "EdFramework.xcframework"
let localFrameworkAbsolutePath = packageRoot.appendingPathComponent(localFrameworkPath).path

// Updated automatically by onde-ed's release-sdk-swift workflow.
let releaseFrameworkURL =
    "https://github.com/ondeinference/ed/releases/download/v1.2.2/EdFramework.xcframework.zip"
let releaseFrameworkChecksum =
    "eb868939625b71af749912204070c11c061fa3c6d3c37f99a8df92b1ea779db6"

let edFrameworkTarget: Target
if FileManager.default.fileExists(atPath: localFrameworkAbsolutePath) {
    edFrameworkTarget = .binaryTarget(
        name: "EdFramework",
        path: localFrameworkPath
    )
} else {
    edFrameworkTarget = .binaryTarget(
        name: "EdFramework",
        url: releaseFrameworkURL,
        checksum: releaseFrameworkChecksum
    )
}

let package = Package(
    name: "Ed",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        .tvOS(.v16),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Ed", targets: ["Ed"]),
    ],
    targets: [
        edFrameworkTarget,
        .target(
            name: "Ed",
            dependencies: [.target(name: "EdFramework")],
            path: "Sources/Ed",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                .linkedFramework("Metal"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedLibrary("c++"),
                .linkedLibrary("iconv"),
                .linkedLibrary("resolv"),
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "EdTests",
            dependencies: ["Ed"],
            path: "Tests/EdTests"
        ),
    ],
    // UniFFI 0.31's generated async callback shim predates Swift 6's region
    // isolation checks. The hand-written Ed API remains concurrency-safe; the
    // generated bridge compiles in Swift 5 language mode until UniFFI updates.
    swiftLanguageModes: [.v5]
)
