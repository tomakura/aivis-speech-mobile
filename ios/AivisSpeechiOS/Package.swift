// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AivisSpeechiOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AivisSpeechiOS",
            targets: ["AivisSpeechiOS"]
        ),
    ],
    dependencies: [
        .package(path: "../AivisMobileCore"),
        .package(url: "https://github.com/apple/swift-testing.git", exact: "6.2.3"),
    ],
    targets: [
        .target(
            name: "AivisSpeechiOS",
            dependencies: [
                .product(name: "AivisMobileCore", package: "AivisMobileCore"),
            ]
        ),
        .testTarget(
            name: "AivisSpeechiOSTests",
            dependencies: [
                "AivisSpeechiOS",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
