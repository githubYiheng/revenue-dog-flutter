//
//  OfferingsMapperTests.swift
//  三方对账：backend offerings + store-products-ios → SPI `Offerings.fromBackendResponse` → Mapper → == wire fixture；
//  剔除诊断、全部缺商品码 2、单项规则（packageType 表、micros、ISO 周期、currencyCode nil → 12）、购买定位码 5。
//

import Foundation
import XCTest
@_spi(RevenueDogInternal) import RevenueDog
@testable import RevenueDogBridge

final class OfferingsMapperTests: XCTestCase {

    private func assertMatches(_ result: OfferingsMapper.Result, wire: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try channelNormalized(result.map)
        let expected = try Fixtures.json("wire/\(wire)")
        if let diff = deepDiff(actual, expected) { XCTFail("\(wire): \(diff)", file: file, line: line) }
    }

    func testOfferingsMatchWireFixture() throws {
        let result = try OfferingsMapper.map(CatalogFixtures.offerings())
        try assertMatches(result, wire: "offerings-ios.json")
        XCTAssertEqual(result.diagnostics, [
            BridgeDiagnostic(code: "hybrid_package_dropped", detail: "retention_offer/$rc_monthly"),
            BridgeDiagnostic(code: "hybrid_offering_dropped", detail: "retention_offer"),
        ])
        XCTAssertNil(result.missingCurrentOfferingIdentifier)
    }

    func testCurrentDroppedMatchesWireFixture() throws {
        let result = try OfferingsMapper.map(CatalogFixtures.offerings("offerings-current-dropped.json"))
        try assertMatches(result, wire: "offerings-current-dropped-ios.json")
        // current 被剔：warn 由插件打；hybrid_offering_dropped 已记过，不重复。
        XCTAssertEqual(result.missingCurrentOfferingIdentifier, "retention_offer")
        XCTAssertEqual(result.diagnostics, [
            BridgeDiagnostic(code: "hybrid_package_dropped", detail: "retention_offer/$rc_monthly"),
            BridgeDiagnostic(code: "hybrid_offering_dropped", detail: "retention_offer"),
        ])
        let channel = try XCTUnwrap(WireCodec.channelValue(result.map) as? [String: Any])
        XCTAssertTrue(channel["current"] is NSNull, "current 键恒在，值 NSNull")
    }

    /// 裁定 5：原生 offerings 非空但全部 package 无商品 → 码 2，信封 == fixture（非购买路径，无 userCancelled）。
    func testAllProductsMissingThrowsStoreProblem() throws {
        let offerings = try CatalogFixtures.offerings(products: [])
        XCTAssertFalse(offerings.all.isEmpty)
        XCTAssertThrowsError(try OfferingsMapper.map(offerings)) { error in
            XCTAssertEqual((error as? BridgeError)?.code, .storeProblemError)
            let envelope = ErrorEnvelope.make(from: error, path: .general)
            do {
                let actual = try channelNormalized(["code": envelope.code, "message": envelope.message,
                                                    "details": envelope.details])
                let expected = try Fixtures.json("wire/errors/store-problem-2.json")
                if let diff = deepDiff(actual, expected) { XCTFail(diff) }
            } catch { XCTFail("\(error)") }
        }
    }

    /// 原生本就为空（后端没配 offering）→ 不是码 2：`{all: {}, current: null}`。
    func testEmptyNativeOfferingsIsNotAnError() throws {
        let data = Data(#"{"current_offering_id": null, "offerings": []}"#.utf8)
        let result = try OfferingsMapper.map(Offerings.fromBackendResponse(data, products: []))
        let actual = try channelNormalized(result.map)
        XCTAssertNil(deepDiff(actual, ["all": [String: Any](), "current": NSNull()] as [String: Any]))
        XCTAssertEqual(result.diagnostics, [])
        XCTAssertNil(result.missingCurrentOfferingIdentifier)
    }

    /// 原生 current id 不在 all 里（原生侧就没有）→ current null + 补记 hybrid_offering_dropped。
    func testCurrentIdAbsentFromNativeIsRecorded() throws {
        let data = Data(#"""
        {"current_offering_id": "ghost", "offerings": [
          {"identifier": "default", "description": "d",
           "packages": [{"identifier": "$rc_annual", "platform_product_identifier": "premium_annual"}]}]}
        """#.utf8)
        let result = try OfferingsMapper.map(Offerings.fromBackendResponse(data, products: CatalogFixtures.storeProducts()))
        XCTAssertEqual(result.missingCurrentOfferingIdentifier, "ghost")
        XCTAssertEqual(result.diagnostics, [BridgeDiagnostic(code: "hybrid_offering_dropped", detail: "ghost")])
    }

    func testPackageTypeTable() {
        let cases: [(PackageType, String)] = [
            (.lifetime, "lifetime"), (.annual, "annual"), (.sixMonth, "six_month"), (.threeMonth, "three_month"),
            (.twoMonth, "two_month"), (.monthly, "monthly"), (.weekly, "weekly"), (.custom, "custom"),
            (.unknown, "unknown"), (PackageType(rawValue: "$rc_quarterly"), "unknown"),
        ]
        for (type, wire) in cases { XCTAssertEqual(OfferingsMapper.packageType(type), wire, type.rawValue) }
    }

    func testMicrosAreExactDecimal() throws {
        let cases: [(String, Int64)] = [("9.99", 9_990_000), ("0", 0), ("59.99", 59_990_000),
                                        ("0.0000005", 1), ("0.0000004", 0), ("12345.678901", 12_345_678_901)]
        for (text, micros) in cases {
            XCTAssertEqual(try OfferingsMapper.micros(try XCTUnwrap(Decimal(string: text)), path: "p"), micros, text)
        }
    }

    func testIso8601Periods() throws {
        XCTAssertEqual(try OfferingsMapper.iso8601(SubscriptionPeriod(unit: .day, value: 3), path: "p"), "P3D")
        XCTAssertEqual(try OfferingsMapper.iso8601(SubscriptionPeriod(unit: .week, value: 1), path: "p"), "P1W")
        XCTAssertEqual(try OfferingsMapper.iso8601(SubscriptionPeriod(unit: .month, value: 6), path: "p"), "P6M")
        XCTAssertEqual(try OfferingsMapper.iso8601(SubscriptionPeriod(unit: .year, value: 1), path: "p"), "P1Y")
        XCTAssertThrowsError(try OfferingsMapper.iso8601(SubscriptionPeriod(unit: .unknown, value: 1), path: "p")) {
            XCTAssertEqual(($0 as? BridgeError)?.code, .unexpectedBackendResponseError)
        }
    }

    /// 裁定 3：currencyCode 仍为 nil → 码 12（wireKey 指到具体商品）。
    func testNilCurrencyCodeThrows12() throws {
        let products = try CatalogFixtures.storeProducts().map { product -> StoreProduct in
            guard product.productIdentifier == "coin_pack_100" else { return product }
            return StoreProduct(productIdentifier: product.productIdentifier,
                                localizedTitle: product.localizedTitle,
                                localizedDescription: product.localizedDescription,
                                price: product.price,
                                currencyCode: nil,
                                localizedPriceString: product.localizedPriceString)
        }
        XCTAssertThrowsError(try OfferingsMapper.map(CatalogFixtures.offerings(products: products))) { error in
            let bridgeError = error as? BridgeError
            XCTAssertEqual(bridgeError?.code, .unexpectedBackendResponseError)
            XCTAssertEqual(bridgeError?.wireKey, "all.default.availablePackages[3].storeProduct.currencyCode")
        }
    }

    // MARK: - 购买定位（B1 / B2 / B3）

    func testLocateFindsPackage() throws {
        let offerings = try CatalogFixtures.offerings()
        let package = try PackageLocator.locate(in: offerings, offeringIdentifier: "default",
                                                packageIdentifier: "$rc_annual")
        XCTAssertEqual(package.storeProduct?.productIdentifier, "premium_annual")
    }

    func testLocateFailuresAreCode5() throws {
        let offerings = try CatalogFixtures.offerings()
        let misses: [(String, String)] = [
            ("default", "$rc_weekly"),          // offering 在、package 不在
            ("default", "$RC_ANNUAL"),          // B2：精确匹配，大小写不同即不在
            ("nope", "$rc_annual"),             // offering 不在
            ("retention_offer", "$rc_monthly"), // package 在但无商品
        ]
        for (offering, package) in misses {
            XCTAssertThrowsError(try PackageLocator.locate(in: offerings, offeringIdentifier: offering,
                                                           packageIdentifier: package)) { error in
                XCTAssertEqual((error as? BridgeError)?.code, .productNotAvailableForPurchaseError)
                XCTAssertEqual((error as? BridgeError)?.underlyingMessage,
                               "package \(package) not found in offering \(offering)")
            }
        }
    }
}
