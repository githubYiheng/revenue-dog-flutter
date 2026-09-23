//
//  PurchaseResultMapper.swift
//  `purchase(package:)` 结果 → wire `{customerInfo, storeTransaction}`（设计 §3 D3 / B4 / B5、§5.5；
//  fixture `wire/purchase-result.json`、`errors/purchase-cancelled-1.json`、`errors/payment-pending-20.json`）。
//
//  归一顺序（原生取消 / 待定不是错误对象，插件是唯一归一点）：
//    userCancelled → 码 1（details.userCancelled = true）；isPending → 码 20；
//    非取消非待定却无 transactionIdentifier → 码 0（B5，原生契约违规，插件另打 error 日志）；
//    transactionIdentifier 为空串 / productIdentifier / purchaseDate 为 nil → 码 12（§5.5，裁定 3，不吞成 ''）。
//  抛出的错误由插件按 `ErrorPath.purchase` 装信封（全部带 userCancelled）。
//  对照 RC：hybrid-common `purchasePackage` 回 `{customerInfo, productIdentifier, transaction}`，
//  取消走 `ErrorContainer(userCancelled: true)`；偏离：交易 id 为空 fail-loud（RC Dart 吞 ''）、
//  待定抛 20（RC iOS 无待定概念）、无交易信息取码 0（RC iOS 0 / Android 24 不一致，取码表兜底位）。
//

import Foundation
import RevenueDog

public enum PurchaseResultMapper {

    /// B5 码 0 的 underlyingErrorMessage。
    public static let missingTransactionMessage =
        "purchase finished without cancellation or pending state but carried no transaction (native contract violation)"

    /// - Returns: `(map, fallbacks)`，fallbacks 来自 CustomerInfo 映射（裁定 3 权益回退）。
    /// - Throws: `PurchasesError`（码 1）/ `BridgeError`（码 20 / 0 / 12）。
    public static func map(_ result: PurchaseResult, now: Date) throws -> CustomerInfoMapper.Result {
        if result.userCancelled {
            // D3：用原生错误类型承载码 1（原生有该码位）；message 为空 → underlyingErrorMessage ""（fixture）。
            throw PurchasesError(code: .purchaseCancelledError, message: "")
        }
        if result.isPending {
            // 原生无 20 码位（RC 码），插件合成。
            throw BridgeError(.paymentPendingError)
        }
        guard let transactionIdentifier = result.transactionIdentifier else {
            throw BridgeError(.unknownError, underlyingMessage: missingTransactionMessage)
        }
        guard !transactionIdentifier.isEmpty else {
            throw missing("storeTransaction.transactionIdentifier", reason: "native transactionIdentifier is empty")
        }
        guard let productIdentifier = result.productIdentifier else {
            throw missing("storeTransaction.productIdentifier", reason: "native productIdentifier is nil")
        }
        guard let purchaseDate = result.purchaseDate else {
            throw missing("storeTransaction.purchaseDate", reason: "native purchaseDate is nil")
        }
        let customerInfo = try CustomerInfoMapper.map(result.customerInfo, now: now)
        let map: [String: Any?] = [
            "customerInfo": customerInfo.map,
            "storeTransaction": [
                "transactionIdentifier": transactionIdentifier,
                "productIdentifier": productIdentifier,
                "purchaseDate": WireCodec.millis(purchaseDate),
            ] as [String: Any?],
        ]
        return (map: map, fallbacks: customerInfo.fallbacks)
    }

    private static func missing(_ wireKey: String, reason: String) -> BridgeError {
        BridgeError(.unexpectedBackendResponseError, underlyingMessage: "\(reason) at \(wireKey)", wireKey: wireKey)
    }
}
