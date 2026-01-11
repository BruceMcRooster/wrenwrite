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
        // Need this instead of Yams for compatibility with C++ interop mode.
        // See https://github.com/jpsim/Yams/pull/467 for more info on status in main project.
        .package(url: "https://github.com/johnfairh/Yams.git", branch: "cyaml-swift-cpp"),
        .package(
            url: "https://github.com/BruceMcRooster/blahtexml.git",
            revision: "630a2289af5b41b3235e4e263db567b187f30341"
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "WrenWrite",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "Blahtex", package: "blahtexml"),
                "md4c_html",
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .testTarget(
            name: "WrenWriteTests", 
            dependencies: ["WrenWrite"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
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
