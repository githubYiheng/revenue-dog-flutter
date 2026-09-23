// swift-tools-version: 6.0
//
//  RevenueDogBridge —— Flutter 插件的纯函数桥接层（设计 §2 边界、D1）。
//
//  只依赖 Foundation + 原生 RevenueDog 公开面 / SPI（`@_spi(RevenueDogInternal)`），**不 import Flutter**，
//  所以能在开发机上直接 `swift test`，将来需要第二个混合框架时可原样抽成共享层。
//  平台：iOS 16 是产品基线（D7）；macOS 13 只为本机 `swift test`。
//  原生版本精确钉死（D12）：与 `../revenue_dog/Package.swift` 同一条 `exact:`，改版本走钉版本脚本（设计 §7）。
//  对照 RC：purchases-hybrid-common 的 mapper / ErrorContainer 也是独立于 Flutter 的纯映射层，边界照抄。

import PackageDescription

let package = Package(
    name: "RevenueDogBridge",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "RevenueDogBridge", targets: ["RevenueDogBridge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/githubYiheng/revenue-dog-ios", exact: "0.4.1"),
    ],
    targets: [
        .target(
            name: "RevenueDogBridge",
            dependencies: [
                .product(name: "RevenueDog", package: "revenue-dog-ios"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "RevenueDogBridgeTests",
            dependencies: [
                "RevenueDogBridge",
                .product(name: "RevenueDog", package: "revenue-dog-ios"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
