// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Macomon",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Macomon", targets: ["Macomon"])
    ],
    targets: [
        .executableTarget(
            name: "Macomon",
            path: ".",
            exclude: [
                ".DS_Store",
                "Codex-Bild 15. Sept. 2026, 16_57_19.png",
                "Codex-Bild 15. Sept. 2026, 22_20_44.png",
                "Codex-Bild 15. Sept. 2026, 23_26_24.png",
                "Codex-Bild 15. Sept. 2026, 23_26_30.png",
                ".build",
                "CONTRIBUTING.md",
                "dist",
                "README.md",
                "scripts",
                "support"
            ],
            sources: ["Sources/Macomon"],
            resources: [
                .copy("gen1"),
                .copy("gen2"),
                .copy("gen3"),
                .copy("gen4"),
                .copy("gen5"),
                .copy("pets")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
