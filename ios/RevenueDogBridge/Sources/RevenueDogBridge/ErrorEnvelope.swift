//
//  ErrorEnvelope.swift
//  §5.6 错误信封：任意 Error → `(code, message, details)`，插件原样装进 `FlutterError`。
//
//  形状（wire fixture `test/fixtures/wire/errors/*.json` 钉死）：
//    code = 十进制串（永不出非数字，含 "901"）
//    details = {code: Int, message, readableErrorCode, readable_error_code, revdogCode,
//               underlyingErrorMessage, [userCancelled 仅购买路径], [backendCode / httpStatusCode 有值才发键]}
//  message 口径（主代理裁定，两端同）：码在合成短句表（0/1/2/4/5/12/20/22/23）里 → 不论来自原生还是插件合成，
//  `message` / `details.message` 一律取表中短句，原生 message 进 `underlyingErrorMessage`（原生另有 underlyingError 时
//  拼成 "原生 message | underlying 描述"）；表外的码（901 / 902 / 10 …）透传原生 message，
//  `underlyingErrorMessage` = `underlyingError?.localizedDescription ?? ""`。插件合成的 12 另带 `details.wireKey`（与 Dart 同形）。
//  对照 RC：hybrid-common `ErrorContainer`（code / message / info{code, message, readableErrorCode,
//  readable_error_code, underlyingErrorMessage}）形状照抄；偏离（D4）：readable 用 RC Android 式 PascalCase
//  两端同值、我方码名另放 `revdogCode`、900+ 专有码照常发。
//

import Foundation
import RevenueDog

/// 错误发生在哪条路径上（决定路径专用映射与 `userCancelled` 键）。
public enum ErrorPath: Sendable, Equatable {
    /// 普通方法（configure / 身份读取 / CustomerInfo …）。
    case general
    /// `logOut`：我方 14 `invalidAppUserIdError` → RC 22（裁定 6）。
    case logOut
    /// 购买路径（M2）：`details.userCancelled` 恒在（码 1 为 true，其余 false，D3）。
    case purchase
}

/// 插件 / Bridge 自己合成的错误码（原生 `PurchasesErrorCode` 的构造器是 internal，且没有 20 / 22 等 RC 码位）。
/// `name` = `lib/src/generated/error_codes.dart` 的枚举名（即 `revdogCode` / readable 的来源）。
public struct SyntheticErrorCode: Sendable, Hashable {
    public let rawValue: Int
    public let name: String

    public static let unknownError = SyntheticErrorCode(rawValue: 0, name: "unknownError")
    public static let purchaseCancelledError = SyntheticErrorCode(rawValue: 1, name: "purchaseCancelledError")
    public static let storeProblemError = SyntheticErrorCode(rawValue: 2, name: "storeProblemError")
    public static let purchaseInvalidError = SyntheticErrorCode(rawValue: 4, name: "purchaseInvalidError")
    public static let productNotAvailableForPurchaseError = SyntheticErrorCode(
        rawValue: 5, name: "productNotAvailableForPurchaseError")
    public static let unexpectedBackendResponseError = SyntheticErrorCode(
        rawValue: 12, name: "unexpectedBackendResponseError")
    public static let paymentPendingError = SyntheticErrorCode(rawValue: 20, name: "paymentPendingError")
    public static let logOutWithAnonymousUserError = SyntheticErrorCode(
        rawValue: 22, name: "logOutWithAnonymousUserError")
    public static let configurationError = SyntheticErrorCode(rawValue: 23, name: "configurationError")
}

/// Bridge / 插件合成的错误（未配置守卫、参数错、契约非空键为 nil …）。
public struct BridgeError: Error, Sendable, CustomStringConvertible {
    public let code: SyntheticErrorCode
    /// 进 `details.underlyingErrorMessage`：具体原因（英文，排障用）。
    public let underlyingMessage: String
    /// 码 12（契约非空键为 nil）时指出出错的 wire 路径，进 `details.wireKey`（与 Dart `throwWireError` 同形）。
    public let wireKey: String?

    public init(_ code: SyntheticErrorCode, underlyingMessage: String = "", wireKey: String? = nil) {
        self.code = code
        self.underlyingMessage = underlyingMessage
        self.wireKey = wireKey
    }

    public var description: String { "[\(code.name)(\(code.rawValue))] \(underlyingMessage)" }
}

public enum ErrorEnvelope {

    /// 合成错误英文短句表 —— **逐字照抄** `sdk/flutter/lib/src/errors.dart` 的 `syntheticErrorMessages`。
    public static let syntheticMessages: [Int: String] = [
        0: "Unknown error.",
        1: "Purchase was cancelled.",
        2: "There was a problem with the store.",
        4: "One or more of the arguments provided are invalid.",
        5: "The product is not available for purchase.",
        12: "unexpected backend response",
        20: "The payment is pending.",
        22: "LogOut was called but the current user is anonymous.",
        23: "There is an issue with your configuration. Check the underlying error for more details.",
    ]

    public typealias Envelope = (code: String, message: String, details: [String: Any?])

    /// 任意错误 → 信封。
    /// - `PurchasesError`：码原样；message 按上方口径（表内码取短句、表外透传）；logOut 路径 14 → 22（裁定 6）。
    /// - `BridgeError`：合成码 + 码表短句；码 12 带 `wireKey`。
    /// - 其它（含 `CancellationError`）：码 0 + 码表短句，`underlyingErrorMessage` = `localizedDescription`。
    public static func make(from error: any Error, path: ErrorPath) -> Envelope {
        if let error = error as? PurchasesError {
            return make(fromPurchasesError: error, path: path)
        }
        if let error = error as? BridgeError {
            return build(number: error.code.rawValue,
                         revdogCode: error.code.name,
                         message: syntheticMessage(error.code.rawValue),
                         underlyingErrorMessage: error.underlyingMessage,
                         backendCode: nil,
                         httpStatusCode: nil,
                         wireKey: error.wireKey,
                         path: path)
        }
        return build(number: SyntheticErrorCode.unknownError.rawValue,
                     revdogCode: SyntheticErrorCode.unknownError.name,
                     message: syntheticMessage(0),
                     underlyingErrorMessage: error.localizedDescription,
                     backendCode: nil,
                     httpStatusCode: nil,
                     wireKey: nil,
                     path: path)
    }

    private static func make(fromPurchasesError error: PurchasesError, path: ErrorPath) -> Envelope {
        // 裁定 6：匿名用户 logOut —— 我方原生 14，RC 宿主按 22 `logOutWithAnonymousUserError` 写处理。
        // 外层码 / readable 走 RC 22，`revdogCode` 仍是我方 `invalidAppUserIdError`；
        // 22 在短句表里 → message 取短句、原生 message 进 underlyingErrorMessage（wire fixture log-out-anonymous-22.json）。
        let isLogOutMapping = path == .logOut
            && error.code.rawValue == PurchasesErrorCode.invalidAppUserIdError.rawValue
        let number = isLogOutMapping ? SyntheticErrorCode.logOutWithAnonymousUserError.rawValue : error.code.rawValue
        let underlyingDescription = error.underlyingError?.localizedDescription
        let message: String
        let underlyingErrorMessage: String
        if let synthetic = syntheticMessages[number] {
            message = synthetic
            underlyingErrorMessage = [error.message, underlyingDescription]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
        } else {
            message = error.message
            underlyingErrorMessage = underlyingDescription ?? ""
        }
        return build(number: number,
                     revdogCode: error.code.name,
                     readable: isLogOutMapping ? readable(SyntheticErrorCode.logOutWithAnonymousUserError.name) : nil,
                     message: message,
                     underlyingErrorMessage: underlyingErrorMessage,
                     backendCode: error.backendCode,
                     httpStatusCode: error.httpStatusCode,
                     wireKey: nil,
                     path: path)
    }

    private static func build(number: Int,
                              revdogCode: String,
                              readable explicitReadable: String? = nil,
                              message: String,
                              underlyingErrorMessage: String,
                              backendCode: Int?,
                              httpStatusCode: Int?,
                              wireKey: String?,
                              path: ErrorPath) -> Envelope {
        let readableCode = explicitReadable ?? readable(revdogCode)
        var details: [String: Any?] = [
            "code": number,
            "message": message,
            "readableErrorCode": readableCode,
            "readable_error_code": readableCode,
            "revdogCode": revdogCode,
            "underlyingErrorMessage": underlyingErrorMessage,
        ]
        // 排障键：有值才发键（§5.6「无值不发键」）。iOS 原生无 requestId。
        if let backendCode { details["backendCode"] = backendCode }
        if let httpStatusCode { details["httpStatusCode"] = httpStatusCode }
        if let wireKey { details["wireKey"] = wireKey }
        // D3：userCancelled 只在购买路径出现。
        if path == .purchase {
            details["userCancelled"] = number == SyntheticErrorCode.purchaseCancelledError.rawValue
        }
        return (code: String(number), message: message, details: details)
    }

    /// 码 → 码表短句；表里没有的码退回 0 的短句（不会发生：合成码都在表里，测试钉住）。
    static func syntheticMessage(_ number: Int) -> String {
        syntheticMessages[number] ?? syntheticMessages[0]!
    }

    /// `readableErrorCode` = 码名首字母大写（= `readableErrorCodeByNumber`，D4）。
    public static func readable(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }
}
