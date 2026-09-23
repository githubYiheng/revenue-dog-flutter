//
//  ErrorEnvelopeTests.swift
//  §5.6 错误信封：每个 `wire/errors/*.json` 构造一个源错误 → 信封深度相等；logOut 路径 14 → 22；非 PurchasesError → 0。
//  另与 Dart 定稿文件对账：合成短句表 == `lib/src/errors.dart`，readable == `generated/error_codes.dart`。
//

import Foundation
import XCTest
import RevenueDog
@testable import RevenueDogBridge

final class ErrorEnvelopeTests: XCTestCase {

    private struct Case {
        let error: any Error
        let path: ErrorPath
        /// iOS 原生没有 `requestId`（设计 §5.6「iOS 无 requestId」）：比较前从期望里去掉。
        let dropsRequestId: Bool
    }

    private static func underlying(_ text: String) -> NSError {
        NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    /// fixture 文件名 → 源错误（样例值照 fixture README「原生测试按样例值构造源错误」）。
    private static let cases: [String: Case] = [
        "purchase-cancelled-1.json": Case(error: BridgeError(.purchaseCancelledError),
                                          path: .purchase, dropsRequestId: false),
        "payment-pending-20.json": Case(error: BridgeError(.paymentPendingError),
                                        path: .purchase, dropsRequestId: false),
        "log-out-anonymous-22.json": Case(
            error: PurchasesError(code: .invalidAppUserIdError,
                                  message: "logOut called while the current user is anonymous"),
            path: .logOut, dropsRequestId: false),
        "configuration-23.json": Case(
            error: BridgeError(.configurationError,
                               underlyingMessage: "Purchases has not been configured; call Purchases.configure first"),
            path: .general, dropsRequestId: false),
        "unexpected-backend-12.json": Case(
            // 12 在短句表里：外层取短句，原生 message 进 underlyingErrorMessage（主代理 message 口径）。
            error: PurchasesError(code: .unexpectedBackendResponseError,
                                  message: "missing request_date in subscriber response",
                                  httpStatusCode: 200),
            path: .general, dropsRequestId: true),
        "pending-server-901.json": Case(
            error: PurchasesError(code: .purchasePendingServerConfirmation,
                                  message: "HTTP 503",
                                  httpStatusCode: 503,
                                  underlyingError: underlying("HTTP 503")),
            path: .purchase, dropsRequestId: true),
        "rejected-by-server-902.json": Case(
            error: PurchasesError(code: .purchaseRejectedByServer,
                                  message: "Bad parameters x",
                                  httpStatusCode: 400,
                                  underlyingError: underlying("Bad parameters x")),
            path: .purchase, dropsRequestId: true),
    ]

    private func envelopeJSON(_ error: any Error, path: ErrorPath) throws -> Any {
        let envelope = ErrorEnvelope.make(from: error, path: path)
        return try channelNormalized(["code": envelope.code, "message": envelope.message, "details": envelope.details])
    }

    func testEveryErrorFixtureIsCovered() throws {
        XCTAssertEqual(try Fixtures.files(in: "wire/errors"), Self.cases.keys.sorted())
    }

    func testEnvelopesMatchWireFixtures() throws {
        for (name, testCase) in Self.cases.sorted(by: { $0.key < $1.key }) {
            var expected = try XCTUnwrap(Fixtures.json("wire/errors/\(name)") as? [String: Any])
            if testCase.dropsRequestId {
                var details = try XCTUnwrap(expected["details"] as? [String: Any])
                XCTAssertNotNil(details.removeValue(forKey: "requestId"), "\(name): fixture 应带 requestId 样例")
                expected["details"] = details
            }
            let actual = try envelopeJSON(testCase.error, path: testCase.path)
            if let diff = deepDiff(actual, expected) { XCTFail("\(name): \(diff)") }
        }
    }

    /// 14 只在 logOut 路径映射为 22；其它路径保持 14。
    func testInvalidAppUserIdOutsideLogOutStays14() {
        let error = PurchasesError(code: .invalidAppUserIdError, message: "bad id")
        let envelope = ErrorEnvelope.make(from: error, path: .general)
        XCTAssertEqual(envelope.code, "14")
        XCTAssertEqual(envelope.details["readableErrorCode"] as? String, "InvalidAppUserIdError")
        XCTAssertEqual(envelope.details["underlyingErrorMessage"] as? String, "")
        XCTAssertNil(envelope.details["userCancelled"] as Any??)
    }

    func testLogOutPathMaps14To22() {
        let error = PurchasesError(code: .invalidAppUserIdError, message: "当前已是匿名身份，logOut 无意义")
        let envelope = ErrorEnvelope.make(from: error, path: .logOut)
        XCTAssertEqual(envelope.code, "22")
        XCTAssertEqual(envelope.message, "LogOut was called but the current user is anonymous.")
        XCTAssertEqual(envelope.details["code"] as? Int, 22)
        XCTAssertEqual(envelope.details["readableErrorCode"] as? String, "LogOutWithAnonymousUserError")
        XCTAssertEqual(envelope.details["revdogCode"] as? String, "invalidAppUserIdError")
    }

    /// 表内码来自原生：message 取短句，underlying = 原生 message（另有 underlyingError 时 " | " 拼接）。
    func testNativeTableCodeUsesSyntheticMessage() {
        let plain = ErrorEnvelope.make(from: PurchasesError(code: .configurationError, message: "身份未确认"),
                                       path: .general)
        XCTAssertEqual(plain.code, "23")
        XCTAssertEqual(plain.message, ErrorEnvelope.syntheticMessages[23])
        XCTAssertEqual(plain.details["message"] as? String, ErrorEnvelope.syntheticMessages[23])
        XCTAssertEqual(plain.details["underlyingErrorMessage"] as? String, "身份未确认")

        let nested = ErrorEnvelope.make(
            from: PurchasesError(code: .storeProblemError, message: "StoreKit failed",
                                 underlyingError: Self.underlying("SKError 0")),
            path: .general)
        XCTAssertEqual(nested.message, "There was a problem with the store.")
        XCTAssertEqual(nested.details["underlyingErrorMessage"] as? String, "StoreKit failed | SKError 0")
    }

    /// 表外码：message 透传原生，underlying = underlyingError 描述或 ""。
    func testNativeOutOfTableCodePassesMessageThrough() {
        let envelope = ErrorEnvelope.make(
            from: PurchasesError(code: .networkError, message: "The request timed out.",
                                 underlyingError: Self.underlying("NSURLErrorTimedOut")),
            path: .general)
        XCTAssertEqual(envelope.code, "10")
        XCTAssertEqual(envelope.message, "The request timed out.")
        XCTAssertEqual(envelope.details["underlyingErrorMessage"] as? String, "NSURLErrorTimedOut")
        XCTAssertFalse(envelope.details.keys.contains("wireKey"))
    }

    /// 插件合成的 12 带 wireKey（与 Dart throwWireError 同形）。
    func testSynthetic12CarriesWireKey() {
        let envelope = ErrorEnvelope.make(
            from: BridgeError(.unexpectedBackendResponseError, underlyingMessage: "nil at firstSeen", wireKey: "firstSeen"),
            path: .general)
        XCTAssertEqual(envelope.code, "12")
        XCTAssertEqual(envelope.message, "unexpected backend response")
        XCTAssertEqual(envelope.details["wireKey"] as? String, "firstSeen")
    }

    func testLogOutPathOtherErrorsPassThrough() {
        let error = PurchasesError(code: .networkError, message: "offline")
        XCTAssertEqual(ErrorEnvelope.make(from: error, path: .logOut).code, "10")
    }

    func testNonPurchasesErrorIsCode0() throws {
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        for error in [Boom() as any Error, CancellationError()] {
            let envelope = ErrorEnvelope.make(from: error, path: .general)
            XCTAssertEqual(envelope.code, "0")
            XCTAssertEqual(envelope.message, "Unknown error.")
            XCTAssertEqual(envelope.details["code"] as? Int, 0)
            XCTAssertEqual(envelope.details["readableErrorCode"] as? String, "UnknownError")
            XCTAssertEqual(envelope.details["revdogCode"] as? String, "unknownError")
            XCTAssertEqual(envelope.details["underlyingErrorMessage"] as? String, error.localizedDescription)
        }
    }

    func testBackendCodeOnlyWhenPresent() {
        let without = ErrorEnvelope.make(from: PurchasesError(code: .networkError, message: "x"), path: .general)
        XCTAssertFalse(without.details.keys.contains("backendCode"))
        XCTAssertFalse(without.details.keys.contains("httpStatusCode"))
        let with = ErrorEnvelope.make(from: PurchasesError(code: .purchaseRejectedByServer, message: "x",
                                                           backendCode: 7243, httpStatusCode: 400),
                                      path: .general)
        XCTAssertEqual(with.details["backendCode"] as? Int, 7243)
        XCTAssertEqual(with.details["httpStatusCode"] as? Int, 400)
    }

    // MARK: - 与 Dart 定稿文件对账

    private static let dartRoot: URL = Fixtures.root.deletingLastPathComponent().deletingLastPathComponent()

    /// 解析 Dart `const Map<int, String> <name> = { 0: '…', … };` 块。
    private func parseDartIntStringMap(file: String, name: String) throws -> [Int: String] {
        let source = try String(contentsOf: Self.dartRoot.appendingPathComponent(file), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "Map<int, String> \(name) = {"))
        let end = try XCTUnwrap(source.range(of: "};", range: start.upperBound..<source.endIndex))
        let body = source[start.upperBound..<end.lowerBound]
        var result: [Int: String] = [:]
        let regex = try NSRegularExpression(pattern: #"^\s*(\d+):\s*'((?:[^'\\]|\\.)*)',"#, options: [.anchorsMatchLines])
        let text = String(body)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let number = Int(text[Range(match.range(at: 1), in: text)!])!
            result[number] = String(text[Range(match.range(at: 2), in: text)!])
        }
        return result
    }

    func testSyntheticMessagesMatchDart() throws {
        let dart = try parseDartIntStringMap(file: "lib/src/errors.dart", name: "syntheticErrorMessages")
        XCTAssertEqual(dart, ErrorEnvelope.syntheticMessages)
    }

    func testReadableCodesMatchDartTable() throws {
        let dart = try parseDartIntStringMap(file: "lib/src/generated/error_codes.dart", name: "readableErrorCodeByNumber")
        XCTAssertFalse(dart.isEmpty)
        let nativeCodes: [PurchasesErrorCode] = [
            .unknownError, .purchaseCancelledError, .storeProblemError, .purchaseNotAllowedError,
            .purchaseInvalidError, .productNotAvailableForPurchaseError, .productAlreadyPurchasedError,
            .receiptAlreadyInUseError, .invalidReceiptError, .missingReceiptFileError, .networkError,
            .invalidCredentialsError, .unexpectedBackendResponseError, .invalidAppUserIdError,
            .operationAlreadyInProgressError, .unknownBackendError, .invalidAppleSubscriptionKeyError,
            .configurationError, .unsupportedError, .emptySubscriberAttributesError,
            .productDiscountMissingIdentifierError, .customerInfoError, .systemInfoError,
            .offlineConnectionError, .notImplementedError, .purchasePendingServerConfirmation,
            .purchaseRejectedByServer,
        ]
        for code in nativeCodes {
            XCTAssertEqual(ErrorEnvelope.readable(code.name), dart[code.rawValue], "native \(code)")
        }
        let synthetic: [SyntheticErrorCode] = [
            .unknownError, .purchaseCancelledError, .storeProblemError, .purchaseInvalidError,
            .productNotAvailableForPurchaseError, .unexpectedBackendResponseError, .paymentPendingError,
            .logOutWithAnonymousUserError, .configurationError,
        ]
        for code in synthetic {
            XCTAssertEqual(ErrorEnvelope.readable(code.name), dart[code.rawValue], "synthetic \(code.name)")
            XCTAssertNotNil(ErrorEnvelope.syntheticMessages[code.rawValue], "synthetic \(code.name) 缺短句")
        }
    }
}
