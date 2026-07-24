// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "notilog",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "NotilogCore",
            targets: ["NotilogCore"]
        ),
        .executable(
            name: "notilog-cli",
            targets: ["notilog-cli"]
        )
    ],
    targets: [
        .target(
            name: "NotilogCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),

        .executableTarget(
            name: "notilog-cli",
            dependencies: ["NotilogCore"]
        ),


        .testTarget(
            name: "NotilogCoreTests",
            dependencies: [
                "NotilogCore"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
