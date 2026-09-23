//
//  CatalogFixtures.swift
//  M2 目录 fixture 构造：`backend/store-products-ios.json`（键名 = Swift `StoreProduct` 公开 init 参数名，
//  fixture README）→ `[StoreProduct]`；再经 SPI `Offerings.fromBackendResponse(_:products:)` 得原生 Offerings。
//

import Foundation
import XCTest
@_spi(RevenueDogInternal) import RevenueDog

enum CatalogFixtures {

    enum FixtureError: Error { case malformed(String) }

    /// `price` 是十进制字符串 → `Decimal(string:)`（不经浮点）。
    static func decimal(_ raw: Any?, _ key: String) throws -> Decimal {
        guard let text = raw as? String, let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        else { throw FixtureError.malformed(key) }
        return value
    }

    static func period(_ raw: Any?, _ key: String) throws -> SubscriptionPeriod? {
        if raw == nil || raw is NSNull { return nil }
        guard let dict = raw as? [String: Any], let unit = dict["unit"] as? String, let value = dict["value"] as? Int
        else { throw FixtureError.malformed(key) }
        return SubscriptionPeriod(unit: SubscriptionPeriod.Unit(rawValue: unit), value: value)
    }

    static func storeProducts() throws -> [StoreProduct] {
        let root = try XCTUnwrap(Fixtures.json("backend/store-products-ios.json") as? [String: Any])
        let items = try XCTUnwrap(root["products"] as? [[String: Any]])
        return try items.map { item in
            let id = try XCTUnwrap(item["productIdentifier"] as? String)
            var offer: IntroductoryOffer?
            if let raw = item["introductoryOffer"] as? [String: Any] {
                offer = IntroductoryOffer(
                    type: IntroductoryOffer.OfferType(rawValue: try XCTUnwrap(raw["type"] as? String)),
                    period: try XCTUnwrap(period(raw["period"], "\(id).introductoryOffer.period")),
                    periodCount: try XCTUnwrap(raw["periodCount"] as? Int),
                    price: try decimal(raw["price"], "\(id).introductoryOffer.price"),
                    displayPrice: try XCTUnwrap(raw["displayPrice"] as? String),
                    isEligible: try XCTUnwrap(raw["isEligible"] as? Bool))
            }
            return StoreProduct(productIdentifier: id,
                                localizedTitle: try XCTUnwrap(item["localizedTitle"] as? String),
                                localizedDescription: try XCTUnwrap(item["localizedDescription"] as? String),
                                price: try decimal(item["price"], "\(id).price"),
                                currencyCode: item["currencyCode"] as? String,
                                localizedPriceString: try XCTUnwrap(item["localizedPriceString"] as? String),
                                subscriptionPeriod: try period(item["subscriptionPeriod"], "\(id).subscriptionPeriod"),
                                introductoryOffer: offer)
        }
    }

    static func offerings(_ backend: String = "offerings.json", products: [StoreProduct]? = nil) throws -> Offerings {
        try Offerings.fromBackendResponse(Fixtures.data("backend/\(backend)"), products: products ?? storeProducts())
    }
}
