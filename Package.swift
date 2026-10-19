// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "rivulet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RivuletCore", targets: ["RivuletCore"]),
        .library(name: "RivuletApp", targets: ["RivuletApp"]),
        .executable(name: "rivulet", targets: ["rivulet"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.2"),
        .package(url: "https://github.com/vapor/console-kit.git", from: "4.14.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-kit.git", from: "1.57.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.36.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.16.1"),
        .package(url: "https://github.com/nmdias/FeedKit.git", from: "10.9.4"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.14.3"),
    ],
    targets: [
        .target(
            name: "RivuletCore",
            dependencies: [
                .product(name: "FluentKit", package: "fluent-kit"),
                .product(name: "SQLKit", package: "sql-kit"),
                .product(name: "FeedKit", package: "FeedKit"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .target(
            name: "RivuletApp",
            dependencies: [
                "RivuletCore",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "ConsoleKit", package: "console-kit"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "rivulet",
            dependencies: [
                "RivuletApp",
                .product(name: "ConsoleKit", package: "console-kit"),
            ]
        ),
        .testTarget(
            name: "RivuletCoreTests",
            dependencies: ["RivuletCore"]
        ),
        .testTarget(
            name: "RivuletAppTests",
            dependencies: [
                "RivuletApp",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "RivuletIntegrationTests",
            dependencies: [
                "RivuletCore",
                "RivuletApp",
                .product(name: "XCTVapor", package: "vapor"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "SQLKit", package: "sql-kit"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
