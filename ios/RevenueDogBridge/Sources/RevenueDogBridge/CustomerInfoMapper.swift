//
//  CustomerInfoMapper.swift
//  原生 `CustomerInfo` → wire map（设计 §5.1 / §5.1b / §5.2 / §5.5 非订阅交易）。
//
//  与 `sdk/flutter/test/fixtures/wire/customer-info-*.json` 逐键一致（Bridge 测试三方对账）。
//  规则：键名 = RC Dart 字段名；时间 = epoch 毫秒 Int；枚举小写；可空键必须在（值 nil）。
//  桥接不做静默默认，只有一条文档化回退：权益 `originalPurchaseDate` 空 → `latestPurchaseDate`（裁定 3）。
//  契约非空而原生为 nil（firstSeen / requestDate / 权益 latestPurchaseDate / 订阅与非订阅 purchaseDate）→ 码 12。
//  对照 RC：hybrid-common `CustomerInfo+HybridAdditions.dictionary` / `EntitlementInfo+HybridAdditions`，
//  字段集与键名照抄；偏离（D2）：时间发毫秒而非 ISO 串 + 另附 `…Millis`，枚举发小写串而非 RC 大写名。
//

import Foundation
import RevenueDog

public enum CustomerInfoMapper {

    /// 映射结果：wire map + 本次用到的文档化回退项（插件据此记 `hybrid_field_fallback` 诊断）。
    public typealias Result = (map: [String: Any?], fallbacks: [String])

    /// - Parameters:
    ///   - info: 原生 CustomerInfo。
    ///   - now: 计算 `entitlements.active` 的参照「现在」（原生再按 3 天 grace 决定用 requestDate 还是 now）。
    /// - Returns: `(map, fallbacks)`；fallbacks 元素形如 `entitlements.premium.originalPurchaseDate`。
    /// - Throws: `BridgeError`（码 12）—— 契约非空键为 nil。
    public static func map(_ info: CustomerInfo, now: Date) throws -> Result {
        var fallbacks: [String] = []

        // ---- entitlements：all 全量；active = 原生 active(now:) 的子集；isActive = 是否在 active 里（08 R7）----
        let activeIDs = Set(info.entitlements.active(now: now).keys)
        var all: [String: Any?] = [:]
        var active: [String: Any?] = [:]
        for (identifier, entitlement) in info.entitlements.all {
            let isActive = activeIDs.contains(identifier)
            let mapped = try mapEntitlement(entitlement, key: identifier, isActive: isActive, fallbacks: &fallbacks)
            all[identifier] = mapped
            if isActive { active[identifier] = mapped }
        }
        let entitlements: [String: Any?] = [
            "all": all,
            "active": active,
            // 我方无 Trusted Entitlements，如实报 not_requested（§5.2 文档化常量）。
            "verification": "not_requested",
        ]

        // ---- 非订阅交易：原生已按 purchaseDate 升序、同时间按 transactionIdentifier 升序（R6）----
        var nonSubscriptionTransactions: [Any?] = []
        for transaction in info.nonSubscriptionTransactions {
            guard let purchaseDate = transaction.purchaseDate else {
                throw missing("nonSubscriptionTransactions[\(transaction.transactionIdentifier)].purchaseDate")
            }
            let mapped: [String: Any?] = [
                "transactionIdentifier": transaction.transactionIdentifier,
                "productIdentifier": transaction.productIdentifier,
                "purchaseDate": WireCodec.millis(purchaseDate),
            ]
            nonSubscriptionTransactions.append(mapped)
        }

        // ---- 订阅明细（§5.1b，RC 19 字段全量）----
        var subscriptions: [String: Any?] = [:]
        for (productID, subscription) in info.subscriptionsByProductIdentifier {
            subscriptions[productID] = try mapSubscription(subscription, key: productID)
        }

        guard let firstSeen = info.firstSeen else { throw missing("firstSeen") }
        guard let requestDate = info.requestDate else { throw missing("requestDate") }

        let map: [String: Any?] = [
            "entitlements": entitlements,
            "activeSubscriptions": info.activeSubscriptionProductIdentifiers.sorted(),
            "allPurchasedProductIdentifiers": info.allPurchasedProductIdentifiers.sorted(),
            "latestExpirationDate": WireCodec.millis(info.latestExpirationDate),
            "firstSeen": WireCodec.millis(firstSeen),
            "originalAppUserId": info.originalAppUserID,
            "requestDate": WireCodec.millis(requestDate),
            "allExpirationDates": info.allExpirationDates.mapValues { date -> Any? in WireCodec.millis(date) },
            "allPurchaseDates": info.allPurchaseDates.mapValues { date -> Any? in WireCodec.millis(date) },
            "originalApplicationVersion": info.originalApplicationVersion,
            "originalPurchaseDate": WireCodec.millis(info.originalPurchaseDate),
            "managementURL": info.managementURL?.absoluteString,
            "nonSubscriptionTransactions": nonSubscriptionTransactions,
            "subscriptionsByProductIdentifier": subscriptions,
        ]
        return (map: map, fallbacks: fallbacks)
    }

    // MARK: - EntitlementInfo（§5.2）

    private static func mapEntitlement(_ entitlement: EntitlementInfo,
                                       key: String,
                                       isActive: Bool,
                                       fallbacks: inout [String]) throws -> [String: Any?] {
        let path = "entitlements.\(key)"
        guard let latestPurchaseDate = entitlement.latestPurchaseDate else {
            throw missing("\(path).latestPurchaseDate")
        }
        let originalPurchaseDate: Date
        if let date = entitlement.originalPurchaseDate {
            originalPurchaseDate = date
        } else {
            // 裁定 3：RC 该字段非空；空 → 回退 latestPurchaseDate 并记诊断（插件据 fallbacks 记）。
            originalPurchaseDate = latestPurchaseDate
            fallbacks.append("\(path).originalPurchaseDate")
        }
        return [
            "identifier": entitlement.identifier,
            "isActive": isActive,
            "willRenew": entitlement.willRenew,
            "periodType": WireCodec.periodType(entitlement.periodType),
            "latestPurchaseDate": WireCodec.millis(latestPurchaseDate),
            "originalPurchaseDate": WireCodec.millis(originalPurchaseDate),
            "expirationDate": WireCodec.millis(entitlement.expirationDate),
            "store": WireCodec.store(entitlement.store),
            "productIdentifier": entitlement.productIdentifier,
            "productPlanIdentifier": entitlement.productPlanIdentifier,
            "isSandbox": entitlement.isSandbox,
            "unsubscribeDetectedAt": WireCodec.millis(entitlement.unsubscribeDetectedAt),
            "billingIssueDetectedAt": WireCodec.millis(entitlement.billingIssueDetectedAt),
            "ownershipType": WireCodec.ownershipType(entitlement.ownershipType),
            "verification": "not_requested",
        ]
    }

    // MARK: - SubscriptionInfo（§5.1b）

    private static func mapSubscription(_ subscription: SubscriptionInfo, key: String) throws -> [String: Any?] {
        guard let purchaseDate = subscription.purchaseDate else {
            throw missing("subscriptionsByProductIdentifier.\(key).purchaseDate")
        }
        return [
            "productIdentifier": subscription.productIdentifier,
            "purchaseDate": WireCodec.millis(purchaseDate),
            "originalPurchaseDate": WireCodec.millis(subscription.originalPurchaseDate),
            "expiresDate": WireCodec.millis(subscription.expiresDate),
            "store": WireCodec.store(subscription.store),
            "unsubscribeDetectedAt": WireCodec.millis(subscription.unsubscribeDetectedAt),
            "isSandbox": subscription.isSandbox,
            "billingIssuesDetectedAt": WireCodec.millis(subscription.billingIssuesDetectedAt),
            "gracePeriodExpiresDate": WireCodec.millis(subscription.gracePeriodExpiresDate),
            "ownershipType": WireCodec.ownershipType(subscription.ownershipType),
            "periodType": WireCodec.periodType(subscription.periodType),
            "refundedAt": WireCodec.millis(subscription.refundedAt),
            // 注意键名是小写 `Id`（RC Dart `SubscriptionInfo.storeTransactionId`）。
            "storeTransactionId": subscription.storeTransactionID,
            "isActive": subscription.isActive,
            "willRenew": subscription.willRenew,
            "autoResumeDate": WireCodec.millis(subscription.autoResumeDate),
            "displayName": subscription.displayName,
            "managementURL": subscription.managementURL?.absoluteString,
            "productPlanIdentifier": subscription.productPlanIdentifier,
        ]
    }

    private static func missing(_ wireKey: String) -> BridgeError {
        BridgeError(.unexpectedBackendResponseError,
                    underlyingMessage: "native CustomerInfo field is nil (contract requires a value) at \(wireKey)",
                    wireKey: wireKey)
    }
}
