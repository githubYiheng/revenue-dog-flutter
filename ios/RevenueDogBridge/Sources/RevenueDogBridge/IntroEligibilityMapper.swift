//
//  IntroEligibilityMapper.swift
//  `checkTrialOrIntroductoryPriceEligibility` → wire `{<productId>: {status, description}}`
//  （设计 §1 #19、§5.5，ADR 0100 第 2 条；fixture `wire/intro-eligibility-ios.json`）。
//
//  派生（iOS）：`offerings()` 里所有 package 的 `storeProduct` 按 `productIdentifier` 建索引；每个请求 id：
//    不在索引 → unknown；在但 `introductoryOffer == nil` → no_intro_offer_exists；
//    有优惠且 `isEligible` → eligible，否则 ineligible。
//  对照 RC：iOS 直查 StoreKit（`checkTrialOrIntroDiscountEligibility`），description 前三句取 RC iOS
//  `IntroEligibility.description` 原文、unknown 取 RC Android hybrid 原文；
//  偏离：由 offerings 派生（不在 offerings 里的商品报 unknown），不单独打 StoreKit。
//

import Foundation
import RevenueDog

public enum IntroEligibilityMapper {

    /// status → description（逐字取 fixture `wire/intro-eligibility-ios.json` / README 表）。
    public static let descriptions: [String: String] = [
        "eligible": "Eligible for trial or introductory price.",
        "ineligible": "Not eligible for trial or introductory price.",
        "no_intro_offer_exists": "Product does not have trial or introductory price.",
        "unknown": "Status indeterminate.",
    ]

    /// 原生 offerings 里全部有商品的 package 的 `StoreProduct`（按 productIdentifier；同 id 多处出现取第一个，
    /// 值相同 —— 原生按商品 id 统一填充）。不经剔除规则：剔除只影响目录展示，不影响资格判断。
    public static func productIndex(_ offerings: Offerings) -> [String: StoreProduct] {
        var index: [String: StoreProduct] = [:]
        for offeringID in offerings.all.keys.sorted() {
            for package in offerings.all[offeringID]?.availablePackages ?? [] {
                guard let product = package.storeProduct, index[product.productIdentifier] == nil else { continue }
                index[product.productIdentifier] = product
            }
        }
        return index
    }

    public static func status(for productIdentifier: String, in index: [String: StoreProduct]) -> String {
        guard let product = index[productIdentifier] else { return "unknown" }
        guard let offer = product.introductoryOffer else { return "no_intro_offer_exists" }
        return offer.isEligible ? "eligible" : "ineligible"
    }

    /// 每个请求的 id 都有条目（Dart 校验，缺 → 码 12）；重复 id 合并。
    public static func map(productIdentifiers: [String], offerings: Offerings) -> [String: Any?] {
        let index = productIndex(offerings)
        var map: [String: Any?] = [:]
        for identifier in productIdentifiers {
            let status = status(for: identifier, in: index)
            map[identifier] = ["status": status, "description": descriptions[status]] as [String: Any?]
        }
        return map
    }
}
