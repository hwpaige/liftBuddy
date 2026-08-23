// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "liftBuddyKit",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15),
    ],
    products: [
        .library(name: "liftBuddyKit", targets: ["liftBuddyKit"]),
        // Racing engine and chart rendering, shared by the watch and the phone
        // so both run exactly the same code rather than two lookalikes.
        .library(name: "liftBuddyUI", targets: ["liftBuddyUI"]),
    ],
    targets: [
        .target(name: "liftBuddyKit"),
        .target(name: "liftBuddyUI", dependencies: ["liftBuddyKit"]),
        .testTarget(name: "liftBuddyKitTests", dependencies: ["liftBuddyKit"]),
    ]
)
