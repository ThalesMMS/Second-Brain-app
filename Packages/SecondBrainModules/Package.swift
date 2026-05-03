// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SecondBrainModules",
    platforms: [
        .iOS("26.4"),
        .macOS("14.0"),
        .watchOS("11.0"),
    ],
    products: [
        .library(name: "SecondBrainDomain", targets: ["SecondBrainDomain"]),
        .library(name: "SecondBrainComposition", targets: ["SecondBrainComposition"]),
        .library(name: "SecondBrainAI", targets: ["SecondBrainAI"]),
        .library(name: "SecondBrainPersistence", targets: ["SecondBrainPersistence"]),
        .library(name: "SecondBrainAudio", targets: ["SecondBrainAudio"]),
    ],
    targets: [
        .target(
            name: "SecondBrainDomain",
            path: "Sources/SecondBrainDomain"
        ),
        .target(
            name: "SecondBrainPersistence",
            dependencies: ["SecondBrainDomain"],
            path: "Sources/SecondBrainPersistence"
        ),
        .target(
            name: "SecondBrainAudio",
            dependencies: ["SecondBrainDomain"],
            path: "Sources/SecondBrainAudio"
        ),
        .target(
            name: "SecondBrainAI",
            dependencies: ["SecondBrainDomain"],
            path: "Sources/SecondBrainAI",
            swiftSettings: [
                .define("ENABLE_WATCH_CONNECTIVITY", .when(platforms: [.iOS]))
            ]
        ),
        .target(
            name: "SecondBrainComposition",
            dependencies: [
                "SecondBrainDomain",
                "SecondBrainPersistence",
                "SecondBrainAudio",
                "SecondBrainAI",
            ],
            path: "Sources/SecondBrainComposition"
        ),
        .testTarget(
            name: "SecondBrainDomainTests",
            dependencies: ["SecondBrainDomain"],
            path: "Tests/SecondBrainDomainTests"
        ),
        .testTarget(
            name: "SecondBrainPersistenceTests",
            dependencies: [
                "SecondBrainDomain",
                "SecondBrainPersistence",
            ],
            path: "Tests/SecondBrainPersistenceTests"
        ),
        .testTarget(
            name: "SecondBrainAudioTests",
            dependencies: [
                "SecondBrainDomain",
                "SecondBrainAudio",
            ],
            path: "Tests/SecondBrainAudioTests"
        ),
        .testTarget(
            name: "SecondBrainAITests",
            dependencies: [
                "SecondBrainDomain",
                "SecondBrainAI",
                "SecondBrainPersistence",
            ],
            path: "Tests/SecondBrainAITests"
        ),
        .testTarget(
            name: "SecondBrainCompositionTests",
            dependencies: [
                "SecondBrainDomain",
                "SecondBrainPersistence",
                "SecondBrainComposition",
            ],
            path: "Tests/SecondBrainCompositionTests",
            swiftSettings: [
                .define("ENABLE_TESTING_PERSISTENCE_FACTORY", .when(configuration: .debug))
            ]
        ),
    ]
)
