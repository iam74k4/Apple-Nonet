// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NonetSpike",
    platforms: [.macOS(.v14)],
    targets: [
        // 非公開の MultitouchSupport.framework を dlopen で読む薄い C ラッパー
        .target(
            name: "CMultitouch",
            linkerSettings: [.linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "NonetSpike",
            dependencies: ["CMultitouch"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
