// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WrenWrite",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WrenWrite", targets: ["WrenWrite"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "WrenWrite",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                "md4c_html",
            ],
        ),
        .testTarget(name: "WrenWriteTests", dependencies: ["WrenWrite"]),
        .target(
            name: "md4c_html",
            path: "Sources/md4c",
            sources: [
                "src/entity.h",
                "src/md4c.h",
                "src/md4c-html.h",
                "src/entity.c",
                "src/md4c.c",
                "src/md4c-html.c",
            ],
            publicHeadersPath: "."
        ),
    ]
)
