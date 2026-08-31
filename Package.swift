// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppLock",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "AppLockCore", targets: ["AppLockCore"]),
        .executable(name: "AppLock", targets: ["AppLock"])
    ],
    targets: [
        .target(name: "AppLockCore"),
        .executableTarget(name: "AppLock", dependencies: ["AppLockCore"])
    ]
)
