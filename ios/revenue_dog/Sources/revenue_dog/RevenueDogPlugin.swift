//
//  RevenueDogPlugin.swift
//  RevenueDog Flutter 插件（iOS）：通道分派、未配置守卫、R3 进程级记录、每引擎一条 CustomerInfo 订阅（D14）；
//  M2 目录与购买（getOfferings / purchasePackage / restore / sync / 试用资格，设计 §3、§5.3–§5.5）。
//
//  设计依据：docs/plan/flutter-sdk-design.md §2 / §4 / §5 / §6。纯映射全部在 RevenueDogBridge（可 swift test）。
//  线程（§6）：Flutter 在主线程调 handle → 本类 @MainActor；CustomerInfo 映射放 Task.detached；
//  `result` 与反向 `invokeMethod` 一律在主线程。
//  对照 RC：purchases_flutter iOS `PurchasesFlutterPlugin`（单通道、方法名 / 事件名、setupPurchases 参数形状）照抄；
//  偏离：未配置守卫回码 23（RC 访问未配置单例直接崩）、重复 configure 在插件层按 R3 挡、每引擎一条订阅（RC 单 delegate 互相覆盖）。
//

@preconcurrency import Flutter  // Flutter 头文件无并发标注（FlutterMethodNotImplemented 是可变全局）
import Foundation
import UIKit
import os
@_spi(RevenueDogInternal) import RevenueDog
import RevenueDogBridge

@MainActor
public final class RevenueDogPlugin: NSObject {

    // MARK: 通道常量（与 Dart `lib/src/channel.dart` 逐字一致）

    nonisolated static let channelName = "revenue_dog"
    nonisolated static let customerInfoUpdatedEvent = "Purchases-CustomerInfoUpdated"
    nonisolated static let logHandlerEvent = "Purchases-LogHandlerEvent"

    /// 诊断 code（设计 §5 总则「诊断」，裁定 10）。
    static let warningOptionIgnored = "hybrid_option_ignored"
    static let warningFieldFallback = "hybrid_field_fallback"
    static let warningDuplicateConfigure = "hybrid_duplicate_configure"

    /// 未配置守卫的 underlyingErrorMessage（与 wire fixture `configuration-23.json`、Android 插件同值）。
    static let notConfiguredUnderlying = "Purchases has not been configured; call Purchases.configure first"

    /// 未配置时仍可调用的方法（设计 §4 未配置守卫）。
    static let unguardedMethods: Set<String> = [
        "setupPurchases", "getConfiguredParams", "isConfigured", "setLogLevel", "setLogHandler",
    ]
    /// 需要已配置的方法（M1 + M2）。
    static let guardedMethods: Set<String> = [
        "attachCustomerInfoStream", "getAppUserID", "isAnonymous", "logIn", "logOut", "getCustomerInfo",
        "enableAdServicesAttributionTokenCollection",
        // M2：目录与购买（设计 §1 #12–#24、§3）。
        "getOfferings", "purchasePackage", "restorePurchases", "syncPurchases",
        "checkTrialOrIntroductoryPriceEligibility",
    ]

    /// 购买路径的方法：同步阶段抛出的错误（参数缺失等）也按购买路径装信封（带 userCancelled: false，D3）。
    static let purchasePathMethods: Set<String> = ["purchasePackage"]

    static let logger = Logger(subsystem: "org.revdog.flutter", category: "plugin")

    // MARK: R3 进程级记录（热重启与多引擎共享；首次成功 setupPurchases 写入，之后不变）

    private struct ConfiguredParams {
        let apiKey: String
        let appUserID: String?
    }

    private static var configuredParams: ConfiguredParams?

    /// 已记过的字段回退（`<originalAppUserId>|<wireKey>`），同一用户同一字段每进程只记一次诊断。
    private static var recordedFallbacks: Set<String> = []

    /// 已记过的目录剔除诊断（`<code>|<detail>`），同一 detail 每进程只记一次（getOfferings 会被反复调用）。
    private static var recordedCatalogDiagnostics: Set<String> = []

    // MARK: 引擎级状态

    private let channel: FlutterMethodChannel
    /// 本引擎的 CustomerInfo 订阅（D14）；detach 时取消，**绝不**动原生 SDK。
    private var subscriptionTask: Task<Void, Never>?
    /// 上一条推给本引擎的值：与之 `==` 的跳过（缓存首推与流首值常常相同）。
    private var lastPushedCustomerInfo: CustomerInfo?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }
}

// MARK: - FlutterPlugin

// Flutter 头文件无并发标注；注册 / 分派 / detach 均由引擎在主线程调用，@preconcurrency 让运行时断言主线程。
extension RevenueDogPlugin: @preconcurrency FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = RevenueDogPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        // 只取消本引擎的订阅；原生单例属于进程，其它引擎还在用（RC 3.5.0 关 SDK 的教训）。
        subscriptionTask?.cancel()
        subscriptionTask = nil
        lastPushedCustomerInfo = nil
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let method = call.method
        guard Self.unguardedMethods.contains(method) || Self.guardedMethods.contains(method) else {
            result(FlutterMethodNotImplemented)
            return
        }
        // 未配置守卫：`Purchases.shared` 未配置会 fatalError，守卫必须在任何 shared 访问之前。
        if Self.guardedMethods.contains(method), !Purchases.isConfigured {
            reply(result, error: BridgeError(.configurationError, underlyingMessage: Self.notConfiguredUnderlying))
            return
        }
        let arguments = Arguments(call.arguments)
        do {
            switch method {
            case "setupPurchases":
                try setupPurchases(arguments, result: result)
            case "getConfiguredParams":
                result(getConfiguredParams())
            case "attachCustomerInfoStream":
                try attachCustomerInfoStream(arguments, result: result)
            case "isConfigured":
                result(Purchases.isConfigured)
            case "getAppUserID":
                result(Purchases.shared.appUserID)
            case "isAnonymous":
                result(Purchases.shared.isAnonymous)
            case "setLogLevel":
                try setLogLevel(arguments, result: result)
            case "setLogHandler":
                setLogHandler(result: result)
            case "logIn":
                try logIn(arguments, result: result)
            case "logOut":
                logOut(result: result)
            case "getCustomerInfo":
                getCustomerInfo(result: result)
            case "enableAdServicesAttributionTokenCollection":
                Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()
                result(nil)
            case "getOfferings":
                getOfferings(result: result)
            case "purchasePackage":
                try purchasePackage(arguments, result: result)
            case "restorePurchases":
                restorePurchases(result: result)
            case "syncPurchases":
                syncPurchases(result: result)
            case "checkTrialOrIntroductoryPriceEligibility":
                try checkTrialOrIntroductoryPriceEligibility(arguments, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        } catch {
            reply(result, error: error, path: Self.purchasePathMethods.contains(method) ? .purchase : .general)
        }
    }
}

// MARK: - 配置（setupPurchases / getConfiguredParams / attachCustomerInfoStream / 日志）

extension RevenueDogPlugin {

    /// 参数键见 Dart `lib/src/purchases.dart` `configure`。参数缺失 / 类型错 / 取值不支持 → 码 23（配置类）。
    private func setupPurchases(_ arguments: Arguments, result: @escaping FlutterResult) throws {
        let config = SyntheticErrorCode.configurationError
        // R3 漏网（原生宿主自己配过，或 Dart 侧记录丢了）：原生会静默忽略第二次 configure，这里 fail-loud。
        guard !Purchases.isConfigured else {
            throw BridgeError(config, underlyingMessage: "Purchases is already configured in this process "
                + "(by the host app or an earlier configure); configure only once per process and "
                + "use logIn / logOut to switch users")
        }

        let apiKey = try arguments.requireString("apiKey", code: config)
        let appUserID = try arguments.optionalString("appUserID", code: config)
        let diagnosticsEnabled = try arguments.requireBool("diagnosticsEnabled", code: config)
        let logLevelName = try arguments.optionalString("logLevel", code: config)
        let waitsForLogInBeforeSync = try arguments.optionalBool("waitsForLogInBeforeSync", code: config)
        let baseUrl = try arguments.optionalString("baseUrl", code: config)
        let platformFlavorVersion = try arguments.requireString("platformFlavorVersion", code: config)
        let completedByName = try arguments.requireString("purchasesAreCompletedBy", code: config)
        // 本平台不适用的选项：只校验类型，不进配置；**取值偏离 RC 默认**（宿主真的设了）才在 configure 成功后
        // 记 hybrid_option_ignored —— Dart 总会带这几个键（默认 true / false / nil），按「非 nil 就记」会每次
        // configure 都留固定噪音（主代理裁定）。
        var ignoredOptions: [String] = []
        if try arguments.optionalBool("shouldShowInAppMessagesAutomatically", code: config) == false {
            ignoredOptions.append("shouldShowInAppMessagesAutomatically")
        }
        if try arguments.optionalBool("pendingTransactionsForPrepaidPlansEnabled", code: config) == true {
            ignoredOptions.append("pendingTransactionsForPrepaidPlansEnabled")
        }
        if try arguments.optionalString("userDefaultsSuiteName", code: config) != nil {
            ignoredOptions.append("userDefaultsSuiteName")
        }

        var configuration = Configuration(apiKey: apiKey)
            .with(appUserID: appUserID)
            .with(diagnosticsEnabled: diagnosticsEnabled)
        // R4：configure 前 setLogLevel 的最近值由 Dart 带进来；原生 configure 会用配置覆盖静态级别。
        if let logLevelName {
            guard let level = LogLevelCodec.logLevel(from: logLevelName) else {
                throw BridgeError(config, underlyingMessage: "unsupported logLevel \(logLevelName)")
            }
            configuration = configuration.with(logLevel: level)
        }
        if let waitsForLogInBeforeSync {
            configuration = configuration.with(waitsForLogInBeforeSync: waitsForLogInBeforeSync)
        }
        if let baseUrl {
            guard let url = URL(string: baseUrl), let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http", url.host != nil else {
                throw BridgeError(config, underlyingMessage: "invalid baseUrl \(baseUrl)")
            }
            configuration = configuration.with(baseURL: url)
        }
        switch completedByName {
        case "revenue_dog":
            configuration = configuration.with(purchasesCompletedBy: .revenueDog)
        case "my_app":
            configuration = configuration.with(purchasesCompletedBy: .myApp)
        default:
            throw BridgeError(config, underlyingMessage: "unsupported purchasesAreCompletedBy \(completedByName)")
        }
        // R1：请求头 X-Platform-Flavor: flutter + 插件版本（pubspec 单一来源，经 Dart version.dart 下发）。
        configuration = configuration.with(platformFlavor: "flutter", flavorVersion: platformFlavorVersion)

        let purchases = Purchases.configure(with: configuration)
        Self.configuredParams = ConfiguredParams(apiKey: apiKey, appUserID: appUserID)
        startCustomerInfoSubscription()
        result(nil)

        // 诊断不阻塞 configure 的返回（recordDiagnosticsWarning 内部要等启动收敛）。
        if !ignoredOptions.isEmpty {
            Task { @MainActor in
                for option in ignoredOptions {
                    await purchases.recordDiagnosticsWarning(Self.warningOptionIgnored, detail: option)
                }
            }
        }
    }

    /// R3：进程级记录（首次成功 setupPurchases 的 apiKey / appUserID）。apiKey 为 public key，可回传。
    private func getConfiguredParams() -> [String: Any] {
        let record = Self.configuredParams
        return WireCodec.channelValue([
            "isConfigured": Purchases.isConfigured,
            "apiKey": record?.apiKey,
            "appUserID": record?.appUserID,
        ] as [String: Any?]) as? [String: Any] ?? [:]
    }

    /// R3「相同」分支 / 热重启 / 后台引擎：本引擎未订阅则订阅；已订阅则补推一次当前值
    /// （热重启后 Dart 的最近值已清零，不补推的话监听者拿不到首值，08 §4.3）。
    private func attachCustomerInfoStream(_ arguments: Arguments, result: @escaping FlutterResult) throws {
        let duplicateConfigure = try arguments.optionalBool("duplicateConfigure",
                                                             code: .purchaseInvalidError) ?? false
        let purchases = Purchases.shared
        if subscriptionTask == nil {
            startCustomerInfoSubscription()
        } else if let cached = purchases.cachedCustomerInfo {
            Task { @MainActor [weak self] in await self?.push(cached, force: true) }
        }
        result(nil)
        if duplicateConfigure {
            Task { @MainActor in
                await purchases.recordDiagnosticsWarning(Self.warningDuplicateConfigure, detail: nil)
            }
        }
    }

    /// 可在 configure 前调用（R4：Dart 同时记住最近值，configure 时写进配置）。
    /// 缺参 → 码 4；取值不支持 → 码 23（与 Android 插件同口径）。
    private func setLogLevel(_ arguments: Arguments, result: @escaping FlutterResult) throws {
        let name = try arguments.requireString("level", code: .purchaseInvalidError)
        guard let level = LogLevelCodec.logLevel(from: name) else {
            throw BridgeError(.configurationError, underlyingMessage: "unsupported logLevel \(name)")
        }
        Purchases.logLevel = level
        result(nil)
    }

    /// 原生日志出口是进程级单例：最后一个调 setLogHandler 的引擎接收日志（同 RC）。
    private func setLogHandler(result: @escaping FlutterResult) {
        Purchases.setLogSink(FlutterLogSink(channel: channel))
        result(nil)
    }
}

// MARK: - 身份与 CustomerInfo

extension RevenueDogPlugin {

    private func logIn(_ arguments: Arguments, result: @escaping FlutterResult) throws {
        let appUserID = try arguments.requireString("appUserID", code: .purchaseInvalidError)
        let purchases = Purchases.shared
        Task { @MainActor in
            do {
                let outcome = try await purchases.logIn(appUserID)
                let customerInfo = outcome.customerInfo
                let created = outcome.created
                let box = try await Task.detached(priority: .userInitiated) {
                    let mapped = try LogInResultMapper.map(customerInfo: customerInfo, created: created, now: Date())
                    return WireBox(value: WireCodec.channelValue(mapped.map), fallbacks: mapped.fallbacks)
                }.value
                self.recordFallbacks(box.fallbacks, for: customerInfo)
                result(box.value)
            } catch {
                self.reply(result, error: error, path: .general)
            }
        }
    }

    /// logOut 路径专用映射：原生 14 → 信封 22（裁定 6，ErrorPath.logOut）。
    private func logOut(result: @escaping FlutterResult) {
        let purchases = Purchases.shared
        Task { @MainActor in
            do {
                let customerInfo = try await purchases.logOut()
                result(try await self.mapCustomerInfo(customerInfo))
            } catch {
                self.reply(result, error: error, path: .logOut)
            }
        }
    }

    /// 默认 fetchPolicy（`.cachedOrFetched`），不暴露给 Dart（同 RC）。
    private func getCustomerInfo(result: @escaping FlutterResult) {
        let purchases = Purchases.shared
        Task { @MainActor in
            do {
                let customerInfo = try await purchases.customerInfo()
                result(try await self.mapCustomerInfo(customerInfo))
            } catch {
                self.reply(result, error: error, path: .general)
            }
        }
    }

    /// CustomerInfo → 通道值：映射在 Task.detached 里做（模型 Sendable），回主线程后记回退诊断。
    private func mapCustomerInfo(_ customerInfo: CustomerInfo) async throws -> Any {
        let box = try await Self.mapOffMain(customerInfo)
        recordFallbacks(box.fallbacks, for: customerInfo)
        return box.value
    }

    private nonisolated static func mapOffMain(_ customerInfo: CustomerInfo) async throws -> WireBox {
        try await Task.detached(priority: .userInitiated) {
            let mapped = try CustomerInfoMapper.map(customerInfo, now: Date())
            return WireBox(value: WireCodec.channelValue(mapped.map), fallbacks: mapped.fallbacks)
        }.value
    }

    /// 裁定 3：权益 originalPurchaseDate 回退 → 记 `hybrid_field_fallback`（同一用户同一字段每进程一次）。
    private func recordFallbacks(_ fallbacks: [String], for customerInfo: CustomerInfo) {
        let fresh = fallbacks.filter {
            Self.recordedFallbacks.insert("\(customerInfo.originalAppUserID)|\($0)").inserted
        }
        guard !fresh.isEmpty, Purchases.isConfigured else { return }
        let purchases = Purchases.shared
        Task { @MainActor in
            for detail in fresh {
                await purchases.recordDiagnosticsWarning(Self.warningFieldFallback, detail: detail)
            }
        }
    }
}

// MARK: - 目录与购买（M2，设计 §3 / §5.3–§5.5）

extension RevenueDogPlugin {

    /// 原生 `offerings()`（自带内存缓存）→ 剔除 + 映射（Task.detached）→ 回 map；记剔除诊断（进程内去重）。
    /// 全部缺商品 → 码 2（非购买路径，无 userCancelled，裁定 5）。
    /// 对照 RC：hybrid-common `getOfferings` 直通原生 + `Offerings+HybridAdditions` 映射；剔除规则见 OfferingsMapper。
    private func getOfferings(result: @escaping FlutterResult) {
        let purchases = Purchases.shared
        Task { @MainActor in
            do {
                let offerings = try await purchases.offerings()
                let box = try await Task.detached(priority: .userInitiated) {
                    let mapped = try OfferingsMapper.map(offerings)
                    return CatalogBox(value: WireCodec.channelValue(mapped.map),
                                      diagnostics: mapped.diagnostics,
                                      missingCurrentOfferingIdentifier: mapped.missingCurrentOfferingIdentifier)
                }.value
                if let missing = box.missingCurrentOfferingIdentifier {
                    Self.logger.warning("current offering \(missing, privacy: .public) has no purchasable package; Offerings.current is null")
                }
                self.recordCatalogDiagnostics(box.diagnostics)
                result(box.value)
            } catch {
                self.reply(result, error: error, path: .general)
            }
        }
    }

    /// `{offeringIdentifier, packageIdentifier}` → 按 id 重取原生 Package（B1 / B2）→ `purchase(package:)` → 归一（D3 / B5）。
    /// 全部错误走购买路径信封（`details.userCancelled` 恒在）；901 / 902 等原生错误原样透传（B4）。
    /// 对照 RC：hybrid-common `purchasePackage(_:presentedOfferingContext:…)` 按字符串 id 重取；
    /// 偏离：id 精确匹配（B2）、待定抛 20、无交易信息码 0、交易字段为空码 12。
    private func purchasePackage(_ arguments: Arguments, result: @escaping FlutterResult) throws {
        let offeringIdentifier = try arguments.requireString("offeringIdentifier", code: .purchaseInvalidError)
        let packageIdentifier = try arguments.requireString("packageIdentifier", code: .purchaseInvalidError)
        let purchases = Purchases.shared
        Task { @MainActor in
            do {
                let offerings = try await purchases.offerings()
                let package = try PackageLocator.locate(in: offerings,
                                                        offeringIdentifier: offeringIdentifier,
                                                        packageIdentifier: packageIdentifier)
                let purchaseResult = try await purchases.purchase(package: package)
                let box = try await Task.detached(priority: .userInitiated) {
                    let mapped = try PurchaseResultMapper.map(purchaseResult, now: Date())
                    return WireBox(value: WireCodec.channelValue(mapped.map), fallbacks: mapped.fallbacks)
                }.value
                self.recordFallbacks(box.fallbacks, for: purchaseResult.customerInfo)
                result(box.value)
            } catch {
                self.reply(result, error: error, path: .purchase)
            }
        }
    }

    /// 直通，等原生完成再回 CustomerInfo map（同 RC iOS）。
    private func restorePurchases(result: @escaping FlutterResult) {
        let purchases = Purchases.shared
        Task { @MainActor in
            do {
                let customerInfo = try await purchases.restorePurchases()
                result(try await self.mapCustomerInfo(customerInfo))
            } catch {
                self.reply(result, error: error, path: .general)
            }
        }
    }

    /// 直通并等原生完成（偏离 RC Android 的立即返回，§1 #24）；回 CustomerInfo map，Dart 丢弃。
    private func syncPurchases(result: @escaping FlutterResult) {
        let purchases = Purchases.shared
        Task { @MainActor in
            do {
                let customerInfo = try await purchases.syncPurchases()
                result(try await self.mapCustomerInfo(customerInfo))
            } catch {
                self.reply(result, error: error, path: .general)
            }
        }
    }

    /// `{productIdentifiers: [String]}` → 由原生 offerings 里商品的 `introductoryOffer` 派生（§1 #19，ADR 0100 第 2 条）。
    /// 参数缺失 / 类型错 → 码 4（非购买路径）；offerings 拉取失败 → 原生错误原样。
    private func checkTrialOrIntroductoryPriceEligibility(_ arguments: Arguments,
                                                          result: @escaping FlutterResult) throws {
        let productIdentifiers = try arguments.requireStringList("productIdentifiers", code: .purchaseInvalidError)
        let purchases = Purchases.shared
        Task { @MainActor in
            do {
                let offerings = try await purchases.offerings()
                let map = IntroEligibilityMapper.map(productIdentifiers: productIdentifiers, offerings: offerings)
                result(WireCodec.channelValue(map))
            } catch {
                self.reply(result, error: error, path: .general)
            }
        }
    }

    /// 裁定 5 / 10：剔除的 package / offering → `recordDiagnosticsWarning`；同一 `<code>|<detail>` 每进程只记一次。
    private func recordCatalogDiagnostics(_ diagnostics: [BridgeDiagnostic]) {
        let fresh = diagnostics.filter {
            Self.recordedCatalogDiagnostics.insert("\($0.code)|\($0.detail)").inserted
        }
        guard !fresh.isEmpty, Purchases.isConfigured else { return }
        for diagnostic in fresh {
            Self.logger.warning("\(diagnostic.code, privacy: .public): \(diagnostic.detail, privacy: .public)")
        }
        let purchases = Purchases.shared
        Task { @MainActor in
            for diagnostic in fresh {
                await purchases.recordDiagnosticsWarning(diagnostic.code, detail: diagnostic.detail)
            }
        }
    }
}

// MARK: - 订阅（D14）

extension RevenueDogPlugin {

    /// 每个插件实例（= 每个引擎）一条 Task：先推原生缓存值（非 nil 时）一次，再逐条推 `customerInfoStream`。
    private func startCustomerInfoSubscription() {
        guard subscriptionTask == nil, Purchases.isConfigured else { return }
        let purchases = Purchases.shared
        subscriptionTask = Task { @MainActor [weak self] in
            if let cached = purchases.cachedCustomerInfo {
                await self?.push(cached, force: false)
            }
            for await customerInfo in purchases.customerInfoStream {
                guard let self, !Task.isCancelled else { return }
                await self.push(customerInfo, force: false)
            }
        }
    }

    /// 推一条 `Purchases-CustomerInfoUpdated`；与上一条 `==` 则跳过（force 时不跳）。
    /// 映射失败（契约非空键为 nil，码 12）只打 error 日志不推：事件通道没有错误回路，Dart 保留上一值。
    private func push(_ customerInfo: CustomerInfo, force: Bool) async {
        if !force, customerInfo == lastPushedCustomerInfo { return }
        // 先记再 await：映射期间流里来的同值不会重复推。
        lastPushedCustomerInfo = customerInfo
        do {
            let box = try await Self.mapOffMain(customerInfo)
            guard !Task.isCancelled else { return }
            recordFallbacks(box.fallbacks, for: customerInfo)
            channel.invokeMethod(Self.customerInfoUpdatedEvent, arguments: box.value)
        } catch {
            Self.logger.error("CustomerInfo mapping failed, update not delivered: \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - 错误回复

extension RevenueDogPlugin {

    /// 错误 → `FlutterError`（§5.6 信封）；码 12 另打 error 日志（§5 总则）；
    /// 码 0 同样打 error 日志（B5：购买成功却无交易信息 = 原生契约违规；其它未知错误也值得留痕）。
    private func reply(_ result: FlutterResult, error: any Error, path: ErrorPath = .general) {
        let envelope = ErrorEnvelope.make(from: error, path: path)
        if envelope.code == "12" {
            Self.logger.error("unexpected backend response: \(String(describing: error), privacy: .public)")
        } else if envelope.code == "0" {
            Self.logger.error("unknown error: \(String(describing: error), privacy: .public)")
        }
        result(FlutterError(code: envelope.code,
                            message: envelope.message,
                            details: WireCodec.channelValue(envelope.details)))
    }
}

// MARK: - 辅助类型

/// 映射结果跨 Task.detached → 主线程的载体：值是刚构造、之后只读的 plist 形态字典，没有共享可变状态。
private struct WireBox: @unchecked Sendable {
    let value: Any
    let fallbacks: [String]
}

/// 目录映射结果跨 Task.detached → 主线程的载体（同 WireBox：值刚构造、之后只读）。
private struct CatalogBox: @unchecked Sendable {
    let value: Any
    let diagnostics: [BridgeDiagnostic]
    let missingCurrentOfferingIdentifier: String?
}

/// 通道参数读取（`Int` / `Bool` / `String` / `[String]`；缺失或类型错 → 调用方给定的码，配置类 23、其余 4）。
/// 对照 RC：purchases-hybrid-common 参数缺失自造 `purchaseInvalidError`；配置类用 23 是我方口径（与 Android 插件同）。
private struct Arguments {
    private let values: [String: Any]

    init(_ raw: Any?) {
        values = raw as? [String: Any] ?? [:]
    }

    private func raw(_ key: String) -> Any? {
        guard let value = values[key], !(value is NSNull) else { return nil }
        return value
    }

    func optionalString(_ key: String, code: SyntheticErrorCode) throws -> String? {
        guard let value = raw(key) else { return nil }
        guard let string = value as? String else {
            throw BridgeError(code, underlyingMessage: "argument \(key) must be a String")
        }
        return string
    }

    func requireString(_ key: String, code: SyntheticErrorCode) throws -> String {
        guard let value = try optionalString(key, code: code) else {
            throw BridgeError(code, underlyingMessage: "missing argument \(key)")
        }
        return value
    }

    func optionalBool(_ key: String, code: SyntheticErrorCode) throws -> Bool? {
        guard let value = raw(key) else { return nil }
        // StandardMessageCodec 把 Dart bool 解成 CFBoolean 的 NSNumber；数字 0/1 不当 bool 收。
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw BridgeError(code, underlyingMessage: "argument \(key) must be a bool")
        }
        return number.boolValue
    }

    func requireBool(_ key: String, code: SyntheticErrorCode) throws -> Bool {
        guard let value = try optionalBool(key, code: code) else {
            throw BridgeError(code, underlyingMessage: "missing argument \(key)")
        }
        return value
    }

    /// Dart `List<String>` 经 StandardMessageCodec 解成 `[Any]`（元素 NSString）；非列表 / 含非字符串 → 给定码。
    func requireStringList(_ key: String, code: SyntheticErrorCode) throws -> [String] {
        guard let value = raw(key) else {
            throw BridgeError(code, underlyingMessage: "missing argument \(key)")
        }
        guard let list = value as? [Any] else {
            throw BridgeError(code, underlyingMessage: "argument \(key) must be a List<String>")
        }
        return try list.map { element in
            guard let string = element as? String else {
                throw BridgeError(code, underlyingMessage: "argument \(key) must be a List<String>")
            }
            return string
        }
    }

    func optionalInt(_ key: String, code: SyntheticErrorCode) throws -> Int? {
        guard let value = raw(key) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw BridgeError(code, underlyingMessage: "argument \(key) must be an int")
        }
        // Dart int 超 32 位时编成 Int64，NSNumber.intValue 在 64 位平台无损。
        return number.intValue
    }
}

/// 原生日志 → `Purchases-LogHandlerEvent {logLevel, message}`（§5.7）。
/// `write` 可在任意线程被调：弱引用通道，主线程 FIFO 投递（DispatchQueue.main 保序）；引擎释放后静默丢弃。
private final class FlutterLogSink: LogSink, @unchecked Sendable {
    // 只在 init 写、只在主线程读。
    private weak var channel: FlutterMethodChannel?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func write(level: LogLevel, category: String, message: String, file: String, line: UInt) {
        // off / 未知级别不推（§5.7）。
        guard let wireLevel = LogLevelCodec.wire(from: level) else { return }
        let text = "[\(category)] \(message)"
        DispatchQueue.main.async { [self] in
            channel?.invokeMethod(RevenueDogPlugin.logHandlerEvent,
                                  arguments: ["logLevel": wireLevel, "message": text])
        }
    }
}
