//
//  PurchaseResultMapperTests.swift
//  §5.5 / D3 / B5：PurchaseResult 公开 init（CustomerInfo 经 SPI 工厂）→ Mapper → == wire fixture；
//  取消 / 待定 / 无交易 / 缺字段 → 信封码 1 / 20 / 0 / 12（购买路径）。
//

import Foundation
import XCTest
@_spi(RevenueDogInternal) import RevenueDog
@testable import RevenueDogBridge

final class PurchaseResultMapperTests: XCTestCase {

    private static let now = CustomerInfoMapperTests.now

    private func customerInfo() throws -> CustomerInfo {
        try CustomerInfo.fromBackendResponse(Fixtures.data("backend/customer-info-minimal.json"), now: Self.now)
    }

    private func result(transactionIdentifier: String? = "2000000987654321",
                        productIdentifier: String? = "premium_monthly",
                        purchaseDate: Date? = CustomerInfoMapperTests.now,
                        userCancelled: Bool = false,
                        isPending: Bool = false) throws -> PurchaseResult {
        PurchaseResult(customerInfo: try customerInfo(),
                       transactionIdentifier: transactionIdentifier,
                       productIdentifier: productIdentifier,
                       purchaseDate: purchaseDate,
                       userCancelled: userCancelled,
                       isPending: isPending)
    }

    private func envelope(of result: PurchaseResult) throws -> (error: any Error, json: Any) {
        do {
            _ = try PurchaseResultMapper.map(result, now: Self.now)
        } catch {
            let envelope = ErrorEnvelope.make(from: error, path: .purchase)
            return (error, try channelNormalized(["code": envelope.code, "message": envelope.message,
                                                  "details": envelope.details]))
        }
        throw XCTSkip("expected throw")
    }

    func testSuccessMatchesWireFixture() throws {
        let mapped = try PurchaseResultMapper.map(result(), now: Self.now)
        XCTAssertEqual(mapped.fallbacks, [])
        let actual = try channelNormalized(mapped.map)
        if let diff = deepDiff(actual, try Fixtures.json("wire/purchase-result.json")) { XCTFail(diff) }
    }

    func testUserCancelledIsCode1Envelope() throws {
        let (error, json) = try envelope(of: result(transactionIdentifier: nil, productIdentifier: nil,
                                                    purchaseDate: nil, userCancelled: true))
        XCTAssertTrue(error is PurchasesError)
        if let diff = deepDiff(json, try Fixtures.json("wire/errors/purchase-cancelled-1.json")) { XCTFail(diff) }
    }

    func testPendingIsCode20Envelope() throws {
        let (_, json) = try envelope(of: result(transactionIdentifier: nil, productIdentifier: nil,
                                                purchaseDate: nil, isPending: true))
        if let diff = deepDiff(json, try Fixtures.json("wire/errors/payment-pending-20.json")) { XCTFail(diff) }
    }

    /// B5：非取消非待定却无交易 → 码 0（购买路径 userCancelled: false）。
    func testMissingTransactionIsCode0() throws {
        let (error, json) = try envelope(of: result(transactionIdentifier: nil))
        XCTAssertEqual((error as? BridgeError)?.code, .unknownError)
        let dict = try XCTUnwrap(json as? [String: Any])
        XCTAssertEqual(dict["code"] as? String, "0")
        let details = try XCTUnwrap(dict["details"] as? [String: Any])
        XCTAssertEqual(details["userCancelled"] as? Bool, false)
        XCTAssertEqual(details["underlyingErrorMessage"] as? String, PurchaseResultMapper.missingTransactionMessage)
    }

    func testMissingFieldsAreCode12() throws {
        let cases: [(PurchaseResult, String)] = [
            (try result(productIdentifier: nil), "storeTransaction.productIdentifier"),
            (try result(purchaseDate: nil), "storeTransaction.purchaseDate"),
            (try result(transactionIdentifier: ""), "storeTransaction.transactionIdentifier"),
        ]
        for (input, wireKey) in cases {
            let (error, json) = try envelope(of: input)
            XCTAssertEqual((error as? BridgeError)?.wireKey, wireKey)
            let dict = try XCTUnwrap(json as? [String: Any])
            XCTAssertEqual(dict["code"] as? String, "12", wireKey)
            XCTAssertEqual((dict["details"] as? [String: Any])?["userCancelled"] as? Bool, false)
        }
    }

    /// 取消优先于待定 / 交易字段（原生取消时交易字段本就为 nil）。
    func testCancelWinsOverEverything() throws {
        let (_, json) = try envelope(of: result(userCancelled: true, isPending: true))
        XCTAssertEqual((json as? [String: Any])?["code"] as? String, "1")
    }
}
