//
//  IntroEligibilityMapperTests.swift
//  §1 #19 / ADR 0100 第 2 条：offerings fixture 的商品 → eligibility map == `wire/intro-eligibility-ios.json`。
//

import Foundation
import XCTest
@_spi(RevenueDogInternal) import RevenueDog
@testable import RevenueDogBridge

final class IntroEligibilityMapperTests: XCTestCase {

    func testMatchesWireFixture() throws {
        let map = IntroEligibilityMapper.map(
            productIdentifiers: ["premium_monthly", "premium_annual", "unknown_product"],
            offerings: try CatalogFixtures.offerings())
        let actual = try channelNormalized(map)
        if let diff = deepDiff(actual, try Fixtures.json("wire/intro-eligibility-ios.json")) { XCTFail(diff) }
    }

    func testIneligibleAndNonSubscription() throws {
        let products = try CatalogFixtures.storeProducts().map { product -> StoreProduct in
            guard let offer = product.introductoryOffer else { return product }
            return StoreProduct(productIdentifier: product.productIdentifier,
                                localizedTitle: product.localizedTitle,
                                localizedDescription: product.localizedDescription,
                                price: product.price,
                                currencyCode: product.currencyCode,
                                localizedPriceString: product.localizedPriceString,
                                subscriptionPeriod: product.subscriptionPeriod,
                                introductoryOffer: IntroductoryOffer(type: offer.type, period: offer.period,
                                                                     periodCount: offer.periodCount,
                                                                     price: offer.price,
                                                                     displayPrice: offer.displayPrice,
                                                                     isEligible: false))
        }
        let index = IntroEligibilityMapper.productIndex(try CatalogFixtures.offerings(products: products))
        XCTAssertEqual(IntroEligibilityMapper.status(for: "premium_monthly", in: index), "ineligible")
        XCTAssertEqual(IntroEligibilityMapper.status(for: "lifetime_unlock", in: index), "no_intro_offer_exists")
        // 后台配了但商店查不到的商品 → unknown。
        XCTAssertEqual(IntroEligibilityMapper.status(for: "premium_monthly_discount", in: index), "unknown")
    }

    /// 与 Dart 定稿 fixture 的四句 description 逐字一致（fixture 只覆盖三种状态，ineligible 取 README 表）。
    func testDescriptionsCoverAllStatuses() {
        XCTAssertEqual(Set(IntroEligibilityMapper.descriptions.keys),
                       ["eligible", "ineligible", "no_intro_offer_exists", "unknown"])
        XCTAssertEqual(IntroEligibilityMapper.descriptions["ineligible"],
                       "Not eligible for trial or introductory price.")
    }
}
