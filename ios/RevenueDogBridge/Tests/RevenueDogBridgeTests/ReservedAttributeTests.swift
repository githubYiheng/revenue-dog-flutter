import XCTest
@testable import RevenueDogBridge

/// 保留属性键表对账（rc.4，设计 §5.8）：`ReservedAttribute.allCases` 与 `wire/reserved-attributes.json` 逐行相等（含顺序与值类型）。
final class ReservedAttributeTests: XCTestCase {

    private func rows() throws -> [[String: Any]] {
        let table = try XCTUnwrap(try Fixtures.json("wire/reserved-attributes.json") as? [String: Any])
        XCTAssertEqual(table["method"] as? String, "setReservedAttribute")
        return try XCTUnwrap(table["attributes"] as? [[String: Any]])
    }

    func testCasesMatchFixtureInOrder() throws {
        let rows = try rows()
        XCTAssertEqual(rows.map { $0["key"] as? String }, ReservedAttribute.allCases.map(\.rawValue))
        XCTAssertEqual(rows.map { $0["value"] as? String }, ReservedAttribute.allCases.map(\.valueKind.rawValue))
    }

    func testParseEveryKeyWithValueAndDeletion() throws {
        for attribute in ReservedAttribute.allCases {
            let key = attribute.rawValue
            let present: Any = attribute.valueKind == .bool ? true : "value_1"
            let write = try ReservedAttributeWrite.parse(key: key, value: present)
            let deleted = try ReservedAttributeWrite.parse(key: key, value: nil)
            XCTAssertEqual(try ReservedAttributeWrite.parse(key: key, value: NSNull()), deleted, key)
            switch (write, deleted) {
            case (.email("value_1"), .email(nil)),
                 (.phoneNumber("value_1"), .phoneNumber(nil)),
                 (.attConsentStatus("value_1"), .attConsentStatus(nil)),
                 (.idfa("value_1"), .idfa(nil)),
                 (.idfv("value_1"), .idfv(nil)),
                 (.fbAnonymousID("value_1"), .fbAnonymousID(nil)),
                 (.firebaseAppInstanceID("value_1"), .firebaseAppInstanceID(nil)),
                 (.timezone("value_1"), .timezone(nil)),
                 (.adMeasurementConsent(true), .adMeasurementConsent(nil)),
                 (.fbCampaignIDs("value_1"), .fbCampaignIDs(nil)):
                break
            default:
                XCTFail("\(key) parsed to \(write) / \(deleted)")
            }
        }
    }

    func testEmptyStringPassesThrough() throws {
        // 空串不在插件里改写成 nil：原生两端对空串同样按删除处理。
        XCTAssertEqual(try ReservedAttributeWrite.parse(key: "$idfa", value: ""), .idfa(""))
        XCTAssertEqual(try ReservedAttributeWrite.parse(key: "$adMeasurementConsent", value: false),
                       .adMeasurementConsent(false))
    }

    func testInvalidArgumentsAreCode4() {
        let cases: [(String?, Any?, String)] = [
            (nil, "x", "missing argument key"),
            ("$unknown", "x", "unknown reserved attribute key $unknown"),
            ("$idfa", true, "argument value must be a String for $idfa"),
            ("$idfa", 1, "argument value must be a String for $idfa"),
            ("$adMeasurementConsent", "true", "argument value must be a bool for $adMeasurementConsent"),
            ("$adMeasurementConsent", NSNumber(value: 1), "argument value must be a bool for $adMeasurementConsent"),
        ]
        for (key, value, message) in cases {
            XCTAssertThrowsError(try ReservedAttributeWrite.parse(key: key, value: value)) { error in
                let bridgeError = error as? BridgeError
                XCTAssertEqual(bridgeError?.code, .purchaseInvalidError, message)
                XCTAssertEqual(bridgeError?.underlyingMessage, message)
            }
        }
    }
}
