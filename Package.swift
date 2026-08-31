// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PrivyLock",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "PrivyLockCore", targets: ["PrivyLockCore"]),
        .executable(name: "PrivyLock", targets: ["PrivyLock"])
    ],
    targets: [
        .target(name: "PrivyLockCore", path: "Sources/AppLockCore"),
        .executableTarget(name: "PrivyLock", dependencies: ["PrivyLockCore"], path: "Sources/AppLock")
    ]
)
