// swift-tools-version: 6.0
//
//  revenue_dog —— Flutter 插件 iOS 端（只 SPM，D8；iOS 16，D7）。
//
//  target `revenue_dog` = 插件类（通道分派、未配置守卫、R3 记录、订阅、线程切换），
//  纯映射在独立包 `../RevenueDogBridge`（不依赖 Flutter，可 `swift test`，设计 §2）。
//  原生 RevenueDog 精确钉版本（D12）：与 `../RevenueDogBridge/Package.swift` 同一条 `exact:`，
//  改版本走钉版本脚本（设计 §7，三处一致门禁）。
//  对照 RC：purchases_flutter 的 iOS 插件同样精确钉 PurchasesHybridCommon 版本。

import Foundation
import PackageDescription

/// `../RevenueDogBridge` 必须相对**真实**目录解析：Flutter 构建时把本包以符号链接挂到
/// `<app>/ios/Flutter/ephemeral/Packages/.packages/<插件根目录名>`，SwiftPM 按链接所在位置解析相对路径
/// （`../FlutterFramework` 正是靠这一点指到 Flutter 生成的框架包），直接写 `../RevenueDogBridge` 会落到
/// `.packages/RevenueDogBridge`（不存在）。这里先解开符号链接再取兄弟目录；本地直接打开本包时两者相同。
let bridgePackagePath = URL(fileURLWithPath: Context.packageDirectory)
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .appendingPathComponent("RevenueDogBridge")
    .path

let package = Package(
    name: "revenue_dog",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(name: "revenue-dog", targets: ["revenue_dog"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(path: bridgePackagePath),
        .package(url: "https://github.com/githubYiheng/revenue-dog-ios", exact: "0.4.1"),
    ],
    targets: [
        .target(
            name: "revenue_dog",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "RevenueDogBridge", package: "RevenueDogBridge"),
                .product(name: "RevenueDog", package: "revenue-dog-ios"),
            ],
            resources: [
                // 隐私清单：本插件自身不采集任何数据、不用 required-reason API（原生 RevenueDog 自带清单，见其包）。
                .process("PrivacyInfo.xcprivacy"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
