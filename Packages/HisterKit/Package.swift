// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HisterKit",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "HisterKit", targets: ["HisterKit"])
    ],
    targets: [
        // Not built with the app's approachable-concurrency settings (the
        // app's nonisolated async functions run on their caller's actor).
        // Enabling NonisolatedNonsendingByDefault here crashed the network
        // tests under the URLProtocol stubs (Xcode 27 beta), so
        // the contract is explicit instead: a nonisolated async function in
        // HisterKit does its CPU work after its first real await (network
        // I/O), never before, so it can't tie up a caller on the main actor.
        .target(name: "HisterKit"),
        .testTarget(name: "HisterKitTests", dependencies: ["HisterKit"]),
    ]
)
