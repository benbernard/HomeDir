// swift-tools-version: 6.0

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5)
]

let package = Package(
    name: "fzf-palette",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FzfPaletteCore", targets: ["FzfPaletteCore"]),
        .executable(name: "FzfPaletteApp", targets: ["FzfPaletteApp"]),
        .executable(name: "fzf-palette", targets: ["fzf-palette"])
    ],
    targets: [
        .target(
            name: "FzfPaletteCore",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "FzfPaletteApp",
            dependencies: ["FzfPaletteCore"],
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "fzf-palette",
            dependencies: ["FzfPaletteCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "FzfPaletteCoreTests",
            dependencies: ["FzfPaletteCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "FzfPaletteIntegrationTests",
            dependencies: ["FzfPaletteCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "FzfPaletteUITests",
            dependencies: ["FzfPaletteCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "FzfPaletteBenchmarks",
            dependencies: ["FzfPaletteCore"],
            swiftSettings: swiftSettings
        )
    ]
)
