// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "rivulet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RivuletCore", targets: ["RivuletCore"]),
        .executable(name: "rivulet", targets: ["rivulet"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.2"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.9.0"),
        .package(url: "https://github.com/nmdias/FeedKit.git", from: "10.9.4"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.14.3"),
    ],
    targets: [
        .target(
            name: "RivuletCore",
            dependencies: [
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "FeedKit", package: "FeedKit"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .executableTarget(
            name: "rivulet",
            dependencies: [
                "RivuletCore",
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .testTarget(
            name: "RivuletCoreTests",
            dependencies: ["RivuletCore"]
        ),
    ]
)
