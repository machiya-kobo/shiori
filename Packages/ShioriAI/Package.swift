// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShioriAI",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "ShioriAI", targets: ["ShioriAI"]),
        .library(name: "ShioriAIOnDevice", targets: ["ShioriAIOnDevice"]),
        .executable(name: "shiori-ai-eval", targets: ["shiori-ai-eval"]),
    ],
    targets: [
        // Shiori's optional AI (docs/ai.md): the cloud clients, the
        // engine order and the rules on what may go where. No
        // FoundationModels here, so it builds and tests on any system. The
        // same concurrency contract as HisterKit (Sendable, nonisolated;
        // CPU work after the first real await).
        .target(name: "ShioriAI"),
        // Apple Intelligence (FoundationModels), apart from the rest: the
        // app and the accuracy test run this same engine.
        .target(name: "ShioriAIOnDevice", dependencies: ["ShioriAI"]),
        // The labeller measured against the user's own labelled pages
        // (read-only against Hister): `swift run shiori-ai-eval --help`.
        .executableTarget(name: "shiori-ai-eval", dependencies: ["ShioriAI", "ShioriAIOnDevice"]),
        .testTarget(name: "ShioriAITests", dependencies: ["ShioriAI"]),
    ]
)
