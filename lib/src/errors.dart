import 'package:flutter/services.dart';

import 'generated/error_codes.dart';

/// `PlatformException` → [PurchasesErrorCode]。
///
/// 对照 RC：类名、方法名、签名逐字照 RC `PurchasesErrorHelper.getErrorCode`。
/// 偏离（D4）：RC 用 `num.parse(e.code)` 后按枚举下标取值（非数字会抛 `FormatException`，900+ 越界）；
/// 我方 `int.tryParse` → 生成码表 [purchasesErrorCodeByNumber] 查找，非数字 / 未知码 → `unknownError`，绝不抛。
class PurchasesErrorHelper {
  /// 返回 `e.code` 对应的错误码；查不到 → [PurchasesErrorCode.unknownError]。
  ///
  /// ```dart
  /// try {
  ///   await Purchases.purchase(PurchaseParams.package(pkg));
  /// } on PlatformException catch (e) {
  ///   switch (PurchasesErrorHelper.getErrorCode(e)) {
  ///     case PurchasesErrorCode.purchaseCancelledError: // 用户取消
  ///     case PurchasesErrorCode.purchasePendingServerConfirmation: // 901：已扣款，稍后到账，绝不引导重买
  ///     default:
  ///   }
  /// }
  /// ```
  static PurchasesErrorCode getErrorCode(PlatformException e) {
    final number = int.tryParse(e.code);
    if (number == null) return PurchasesErrorCode.unknownError;
    return purchasesErrorCodeByNumber[number] ?? PurchasesErrorCode.unknownError;
  }
}

/// 合成错误（Dart 或原生插件自造，而非原生 SDK 抛出）的英文短句表（设计 §5.6「码表英文短句」）。
///
/// 原生插件合成同码错误时 `message` / `details.message` 必须逐字取此表（wire fixture 已钉死）。
/// 文案对照 RC 原生同码错误的描述；码 12 按主代理规格为 `unexpected backend response`。
const Map<int, String> syntheticErrorMessages = {
  0: 'Unknown error.',
  1: 'Purchase was cancelled.',
  2: 'There was a problem with the store.',
  4: 'One or more of the arguments provided are invalid.',
  5: 'The product is not available for purchase.',
  12: 'unexpected backend response',
  20: 'The payment is pending.',
  22: 'LogOut was called but the current user is anonymous.',
  23: 'There is an issue with your configuration. Check the underlying error for more details.',
};

/// 构造 §5.6 错误信封形状的 `PlatformException`（Dart 侧合成错误用）。
///
/// [message] 缺省取 [syntheticErrorMessages]；[extraDetails] 追加到 `details`（如码 12 的 `wireKey`）。
PlatformException buildPurchasesPlatformException(
  PurchasesErrorCode code, {
  String? message,
  String underlyingErrorMessage = '',
  Map<String, Object?> extraDetails = const {},
}) {
  final number = purchasesErrorCodeByNumber.entries.firstWhere((e) => e.value == code).key;
  final readable = readableErrorCodeByNumber[number]!;
  final text = message ?? syntheticErrorMessages[number] ?? readable;
  return PlatformException(
    code: '$number',
    message: text,
    details: <String, Object?>{
      'code': number,
      'message': text,
      'readableErrorCode': readable,
      'readable_error_code': readable,
      'revdogCode': code.name,
      'underlyingErrorMessage': underlyingErrorMessage,
      ...extraDetails,
    },
  );
}
