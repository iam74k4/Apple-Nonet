// swift-tools-version: 6.0
import PackageDescription

/// アプリ以外のすべて。設計は docs/architecture.md を参照
let package = Package(
    name: "NonetKit",
    defaultLocalization: "ja",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NonetCore", targets: ["NonetCore"]),
        .library(name: "NonetPlatform", targets: ["NonetPlatform"]),
        .library(name: "NonetUI", targets: ["NonetUI"]),
        .executable(name: "nonet-license", targets: ["NonetLicenseTool"]),
    ],
    targets: [
        // AppKit を使わない純粋なロジック。Swift 6 の言語モード
        .target(
            name: "NonetCore",
            resources: [.process("Resources")]
        ),
        // 非公開の MultitouchSupport.framework を dlopen で読む C ラッパー
        .target(
            name: "CMultitouch",
            linkerSettings: [.linkedFramework("CoreFoundation")]
        ),
        // NonetCore のサービス protocol の macOS 実装
        .target(
            name: "NonetPlatform",
            dependencies: ["NonetCore", "CMultitouch"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // 画面（SwiftUI / AppKit）。NonetPlatform には依存しない
        .target(
            name: "NonetUI",
            dependencies: ["NonetCore"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // ライセンスキーの鍵生成と発行
        .executableTarget(
            name: "NonetLicenseTool",
            dependencies: ["NonetCore"]
        ),
        .testTarget(
            name: "NonetCoreTests",
            dependencies: ["NonetCore"]
        ),
        .testTarget(
            name: "NonetPlatformTests",
            dependencies: ["NonetPlatform", "NonetCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NonetUITests",
            dependencies: ["NonetUI", "NonetCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
