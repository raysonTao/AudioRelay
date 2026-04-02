// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioRelayReceiver",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .systemLibrary(
            name: "COpus",
            path: "Sources/COpus",
            pkgConfig: "opus",
            providers: [
                .brew(["opus"])
            ]
        ),
        .target(
            name: "COpusHelpers",
            dependencies: ["COpus"],
            path: "Sources/COpusHelpers",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "AudioRelayReceiver",
            dependencies: ["COpus", "COpusHelpers"],
            path: "Sources/AudioRelayReceiver"
        ),
    ]
)
