//
//  OfferingsMapper.swift
//  原生 `Offerings` → wire map（设计 §5.3 / §5.4，裁定 5；fixture `wire/offerings-ios.json`、
//  `wire/offerings-current-dropped-ios.json`、`wire/errors/store-problem-2.json`）。
//
//  剔除规则（裁定 5）：
//    1. package 的 `storeProduct == nil`（商店查不到）→ 剔除，记 `hybrid_package_dropped`（detail `<offering>/<package>`）；
//    2. 剔空的 offering 从 `all` 去掉，记 `hybrid_offering_dropped`（detail `<offering>`）；
//    3. 原生 `all` 非空而剔后为空 → 抛码 2（`store products unavailable`，非购买路径，无 userCancelled）；
//    4. `current` = 剔后 `all[currentOfferingIdentifier]`，没有 → null（键恒在）+ 插件 warn；
//       原生 current id 非 nil 而剔后不存在、且本次尚未记该 offering 的 `hybrid_offering_dropped` → 补记。
//  对照 RC：hybrid-common `Offerings+HybridAdditions` / `Package+HybridAdditions` / `StoreProduct+HybridAdditions`
//  的键名照抄（RC `createPackage` 查不到商品即不建 package，剔除后的形态回到 RC）；
//  偏离（D2）：金额只发 int micros（RC 发 double price）、周期发 ISO 串、枚举小写、
//  StoreProduct 也带 `presentedOfferingContext`（RC iOS 不带）、原生全部缺商品抛码 2（RC 行为未核实）。
//

import Foundation
import RevenueDog

/// 插件要记的诊断项（`Purchases.recordDiagnosticsWarning(code, detail:)`）。
public struct BridgeDiagnostic: Sendable, Hashable, CustomStringConvertible {
    public let code: String
    public let detail: String

    public init(code: String, detail: String) {
        self.code = code
        self.detail = detail
    }

    /// 诊断 code（设计 §5 总则「诊断」，裁定 10；与 Android 插件同值）。
    public static let packageDroppedCode = "hybrid_package_dropped"
    public static let offeringDroppedCode = "hybrid_offering_dropped"

    public var description: String { "\(code)(\(detail))" }
}

public enum OfferingsMapper {

    /// 码 2 的 underlyingErrorMessage（与 fixture `store-problem-2.json`、Android 插件同值）。
    public static let storeProductsUnavailable = "store products unavailable"

    public struct Result {
        /// `{all, current}`，`current` 键恒在（nil → 通道上 NSNull）。
        public let map: [String: Any?]
        /// 本次剔除产生的诊断项（按 offering id 字典序、package 保持后台顺序；插件按进程去重后记）。
        public let diagnostics: [BridgeDiagnostic]
        /// 原生 current id 非 nil、剔后却不存在时给出该 id（插件据此打 warn 日志）；否则 nil。
        public let missingCurrentOfferingIdentifier: String?
    }

    /// - Throws: `BridgeError` 码 2（原生非空而全部剔空）/ 码 12（契约非空键为 nil，如 `currencyCode`）。
    public static func map(_ offerings: Offerings) throws -> Result {
        var diagnostics: [BridgeDiagnostic] = []
        var all: [String: Any?] = [:]

        for offeringID in offerings.all.keys.sorted() {
            guard let offering = offerings.all[offeringID] else { continue }
            var packages: [Any?] = []
            for (index, package) in offering.availablePackages.enumerated() {
                guard let product = package.storeProduct else {
                    diagnostics.append(BridgeDiagnostic(code: BridgeDiagnostic.packageDroppedCode,
                                                        detail: "\(offering.identifier)/\(package.identifier)"))
                    continue
                }
                let path = "all.\(offering.identifier).availablePackages[\(index)]"
                packages.append(try mapPackage(package, product: product, path: path))
            }
            guard !packages.isEmpty else {
                diagnostics.append(BridgeDiagnostic(code: BridgeDiagnostic.offeringDroppedCode,
                                                    detail: offering.identifier))
                continue
            }
            // 键用 all 的字典键（原生两者相同：Offerings(wireModel:) 以 identifier 建键）。
            all[offeringID] = [
                "identifier": offering.identifier,
                "serverDescription": offering.serverDescription,
                "availablePackages": packages,
            ] as [String: Any?]
        }

        if !offerings.all.isEmpty, all.isEmpty {
            throw BridgeError(.storeProblemError, underlyingMessage: storeProductsUnavailable)
        }

        var current: Any? = nil
        var missingCurrent: String? = nil
        if let currentID = offerings.currentOfferingIdentifier {
            if let mapped = all[currentID] {
                current = mapped
            } else {
                missingCurrent = currentID
                let dropped = BridgeDiagnostic(code: BridgeDiagnostic.offeringDroppedCode, detail: currentID)
                if !diagnostics.contains(dropped) { diagnostics.append(dropped) }
            }
        }

        return Result(map: ["all": all, "current": current],
                      diagnostics: diagnostics,
                      missingCurrentOfferingIdentifier: missingCurrent)
    }

    // MARK: - Package（§5.3）

    private static func mapPackage(_ package: Package, product: StoreProduct, path: String) throws -> [String: Any?] {
        let context = presentedOfferingContext(package.offeringIdentifier)
        return [
            "identifier": package.identifier,
            "packageType": packageType(package.packageType),
            "offeringIdentifier": package.offeringIdentifier,
            "storeProduct": try mapStoreProduct(product, context: context, path: "\(path).storeProduct"),
            "presentedOfferingContext": context,
        ]
    }

    /// 显式表（D2：不按下标 / 不靠 rawValue 去前缀）。原生把非标准 id 归 `.custom`；
    /// 表外的 rawValue（原生将来新增或宿主自造）→ `unknown`（Dart 值集冻结，未知容忍）。
    /// 对照 RC：hybrid-common 发 `PackageType` 名（`ANNUAL` …），我方发小写（D2）。
    public static func packageType(_ type: PackageType) -> String {
        switch type {
        case .lifetime: return "lifetime"
        case .annual: return "annual"
        case .sixMonth: return "six_month"
        case .threeMonth: return "three_month"
        case .twoMonth: return "two_month"
        case .monthly: return "monthly"
        case .weekly: return "weekly"
        case .custom: return "custom"
        default: return "unknown"
        }
    }

    /// `{offeringIdentifier, placementIdentifier: null, targetingContext: null}`：我方无 placement / targeting（08 R8）。
    static func presentedOfferingContext(_ offeringIdentifier: String) -> [String: Any?] {
        [
            "offeringIdentifier": offeringIdentifier,
            "placementIdentifier": nil,
            "targetingContext": nil,
        ]
    }

    // MARK: - StoreProduct / IntroductoryPrice（§5.4）

    /// 不发的键（Dart 填文档化常量）：`discounts` / `pricePerWeek|Month|Year(+String)`；
    /// iOS `defaultOption` / `subscriptionOptions` 发 null（键在，同 RC iOS）。
    static func mapStoreProduct(_ product: StoreProduct,
                                context: [String: Any?],
                                path: String) throws -> [String: Any?] {
        // 裁定 3：0.4.0 起 StoreKit 路径恒有值；仍缺（宿主自造 fixture）→ 码 12，不静默默认。
        guard let currencyCode = product.currencyCode else {
            throw missing("\(path).currencyCode", reason: "native StoreProduct.currencyCode is nil")
        }
        let subscriptionPeriod = try product.subscriptionPeriod.map {
            try iso8601($0, path: "\(path).subscriptionPeriod")
        }
        return [
            "identifier": product.productIdentifier,
            "title": product.localizedTitle,
            "description": product.localizedDescription,
            "priceAmountMicros": try micros(product.price, path: "\(path).priceAmountMicros"),
            "priceString": product.localizedPriceString,
            "currencyCode": currencyCode,
            "subscriptionPeriod": subscriptionPeriod,
            // 非续期订阅在 iOS 归 non_subscription（与 RC 是否一致未核实，§5.4）。
            "productCategory": product.subscriptionPeriod == nil ? "non_subscription" : "subscription",
            "introductoryPrice": try product.introductoryOffer.map {
                try mapIntroductoryOffer($0, path: "\(path).introductoryPrice")
            },
            "defaultOption": nil,
            "subscriptionOptions": nil,
            "presentedOfferingContext": context,
        ]
    }

    /// 对照 RC：hybrid-common `introductoryPrice` 字典键照抄；偏离：价发 micros（R9 数值价，freeTrial = 0）。
    private static func mapIntroductoryOffer(_ offer: IntroductoryOffer, path: String) throws -> [String: Any?] {
        [
            "priceAmountMicros": try micros(offer.price, path: "\(path).priceAmountMicros"),
            "priceString": offer.displayPrice,
            "period": try iso8601(offer.period, path: "\(path).period"),
            "periodUnit": try unitName(offer.period.unit, path: "\(path).periodUnit"),
            "periodNumberOfUnits": offer.period.value,
            "cycles": offer.periodCount,
        ]
    }

    // MARK: - 数值与周期

    /// `Decimal` × 10⁶ → int64 micros：`NSDecimalNumber` 十进制精确乘，四舍五入（plain）到整数，
    /// 不经 Double（9.99 × 10⁶ 用浮点会得 9989999.999…）。超出 int64 → 码 12。
    public static func micros(_ amount: Decimal, path: String) throws -> Int64 {
        let handler = NSDecimalNumberHandler(roundingMode: .plain, scale: 0,
                                             raiseOnExactness: false, raiseOnOverflow: false,
                                             raiseOnUnderflow: false, raiseOnDivideByZero: false)
        let scaled = NSDecimalNumber(decimal: amount)
            .multiplying(byPowerOf10: 6, withBehavior: handler)
        let value = scaled.decimalValue
        guard !value.isNaN,
              value <= Decimal(Int64.max), value >= Decimal(Int64.min) else {
            throw missing(path, reason: "price \(amount) out of int64 micros range")
        }
        return scaled.int64Value
    }

    /// `SubscriptionPeriod` → ISO 8601 `P<value><D|W|M|Y>`（原始单位，不改写 week → 7 天）。
    /// 未知单位写不出 ISO 串 → 码 12（Apple 目前只有四种单位；不静默改写）。
    static func iso8601(_ period: SubscriptionPeriod, path: String) throws -> String {
        let letter: String
        switch period.unit {
        case .day: letter = "D"
        case .week: letter = "W"
        case .month: letter = "M"
        case .year: letter = "Y"
        default: throw missing(path, reason: "unsupported subscription period unit \(period.unit.rawValue)")
        }
        return "P\(period.value)\(letter)"
    }

    /// `PeriodUnit` wire 值（`day|week|month|year`）；与 `iso8601` 同口径，未知单位 → 码 12。
    static func unitName(_ unit: SubscriptionPeriod.Unit, path: String) throws -> String {
        switch unit {
        case .day, .week, .month, .year: return unit.rawValue
        default: throw missing(path, reason: "unsupported subscription period unit \(unit.rawValue)")
        }
    }

    private static func missing(_ wireKey: String, reason: String) -> BridgeError {
        BridgeError(.unexpectedBackendResponseError, underlyingMessage: "\(reason) at \(wireKey)", wireKey: wireKey)
    }
}

// MARK: - 购买定位（§3 B1 / B2 / B3）

public enum PackageLocator {

    /// 码 5 的 underlyingErrorMessage（格式钉死，fixture `product-not-found-5.json`）。
    public static func notFoundMessage(packageIdentifier: String, offeringIdentifier: String) -> String {
        "package \(packageIdentifier) not found in offering \(offeringIdentifier)"
    }

    /// 按字符串 id 在原生 offerings 里重取 Package（B1，插件不缓存原生对象）；
    /// id **精确匹配**（B2，偏离 RC Android 的忽略大小写）。找不到或该 package 无商品 → 码 5（B3）。
    /// 对照 RC：hybrid-common `purchasePackage` 按 `offeringIdentifier` + `packageIdentifier` 重取，找不到自造
    /// `productNotAvailableForPurchaseError`。
    public static func locate(in offerings: Offerings,
                              offeringIdentifier: String,
                              packageIdentifier: String) throws -> Package {
        guard let offering = offerings.all[offeringIdentifier],
              let package = offering.availablePackages.first(where: { $0.identifier == packageIdentifier }),
              package.storeProduct != nil else {
            throw BridgeError(.productNotAvailableForPurchaseError,
                              underlyingMessage: notFoundMessage(packageIdentifier: packageIdentifier,
                                                                 offeringIdentifier: offeringIdentifier))
        }
        return package
    }
}
