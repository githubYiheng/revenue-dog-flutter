//
//  CustomerInfoMapperTests.swift
//  三方对账：backend fixture → 原生 `CustomerInfo.fromBackendResponse(_:now:)`（SPI）→ Mapper → == wire fixture。
//

import Foundation
import XCTest
@_spi(RevenueDogInternal) import RevenueDog
@testable import RevenueDogBridge

final class CustomerInfoMapperTests: XCTestCase {

    /// 名义参照时间 = fixture 的 `request_date`（fixture README「参照时间」）。
    static let now = Date(timeIntervalSince1970: 1_790_164_800)  // 2026-09-23T12:00:00Z

    private func mapFixture(_ name: String) throws -> CustomerInfoMapper.Result {
        let info = try CustomerInfo.fromBackendResponse(Fixtures.data("backend/\(name)"), now: Self.now)
        return try CustomerInfoMapper.map(info, now: Self.now)
    }

    private func assertMatchesWire(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws
        -> [String] {
        let result = try mapFixture(name)
        let actual = try channelNormalized(result.map)
        let expected = try Fixtures.json("wire/\(name)")
        if let diff = deepDiff(actual, expected) {
            XCTFail("\(name): \(diff)", file: file, line: line)
        }
        return result.fallbacks
    }

    func testReferenceTimeIsRequestDate() {
        XCTAssertEqual(WireCodec.millis(Self.now), 1_790_164_800_000)
    }

    func testMinimal() throws {
        XCTAssertEqual(try assertMatchesWire("customer-info-minimal.json"), [])
    }

    func testFull() throws {
        XCTAssertEqual(try assertMatchesWire("customer-info-full.json"), [])
    }

    func testOriginalPurchaseDateNullFallsBack() throws {
        let fallbacks = try assertMatchesWire("customer-info-original-purchase-date-null.json")
        XCTAssertEqual(fallbacks, ["entitlements.premium.originalPurchaseDate"])
    }

    func testLogInResult() throws {
        let info = try CustomerInfo.fromBackendResponse(Fixtures.data("backend/customer-info-minimal.json"),
                                                        now: Self.now)
        let result = try LogInResultMapper.map(customerInfo: info, created: true, now: Self.now)
        let actual = try channelNormalized(result.map)
        let expected = try Fixtures.json("wire/log-in-result.json")
        if let diff = deepDiff(actual, expected) { XCTFail(diff) }
    }

    /// 可空键必须在（值为 NSNull），不能被丢掉。
    func testNullableKeysArePresentAsNSNull() throws {
        let result = try mapFixture("customer-info-minimal.json")
        let channel = try XCTUnwrap(WireCodec.channelValue(result.map) as? [String: Any])
        XCTAssertTrue(channel["latestExpirationDate"] is NSNull)
        XCTAssertTrue(channel["managementURL"] is NSNull)
        XCTAssertTrue(channel["originalApplicationVersion"] is NSNull)
        XCTAssertTrue(channel["originalPurchaseDate"] is NSNull)
    }

    /// 契约非空键为 nil → 码 12（firstSeen 缺失）。
    func testMissingFirstSeenThrows12() throws {
        let raw = try XCTUnwrap(Fixtures.json("backend/customer-info-minimal.json") as? [String: Any])
        var subscriber = try XCTUnwrap(raw["subscriber"] as? [String: Any])
        subscriber["first_seen"] = NSNull()
        var patched = raw
        patched["subscriber"] = subscriber
        let data = try JSONSerialization.data(withJSONObject: patched)
        let info = try CustomerInfo.fromBackendResponse(data, now: Self.now)
        XCTAssertThrowsError(try CustomerInfoMapper.map(info, now: Self.now)) { error in
            let bridgeError = error as? BridgeError
            XCTAssertEqual(bridgeError?.code, .unexpectedBackendResponseError)
            let envelope = ErrorEnvelope.make(from: error, path: .general)
            XCTAssertEqual(envelope.code, "12")
            XCTAssertEqual(envelope.details["wireKey"] as? String, "firstSeen")
        }
    }

    /// 权益 latestPurchaseDate 与 originalPurchaseDate 皆空 → 码 12。
    func testEntitlementWithoutAnyPurchaseDateThrows12() throws {
        let raw = try XCTUnwrap(Fixtures.json("backend/customer-info-original-purchase-date-null.json")
            as? [String: Any])
        var subscriber = try XCTUnwrap(raw["subscriber"] as? [String: Any])
        var entitlements = try XCTUnwrap(subscriber["entitlements"] as? [String: Any])
        var premium = try XCTUnwrap(entitlements["premium"] as? [String: Any])
        premium["purchase_date"] = NSNull()
        entitlements["premium"] = premium
        subscriber["entitlements"] = entitlements
        var patched = raw
        patched["subscriber"] = subscriber
        let data = try JSONSerialization.data(withJSONObject: patched)
        let info = try CustomerInfo.fromBackendResponse(data, now: Self.now)
        XCTAssertThrowsError(try CustomerInfoMapper.map(info, now: Self.now)) { error in
            XCTAssertEqual((error as? BridgeError)?.code, .unexpectedBackendResponseError)
            XCTAssertEqual((error as? BridgeError)?.wireKey, "entitlements.premium.latestPurchaseDate")
        }
    }
}
