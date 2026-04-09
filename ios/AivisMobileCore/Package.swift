// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AivisMobileCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AivisMobileCore",
            targets: ["AivisMobileCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", exact: "6.2.3"),
    ],
    targets: [
        .target(
            name: "AivisMobileCore"
        ),
        .testTarget(
            name: "AivisMobileCoreTests",
            dependencies: [
                "AivisMobileCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
