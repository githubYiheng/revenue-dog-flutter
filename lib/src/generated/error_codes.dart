// 自动生成，勿手改。
// 生成脚本：scripts/gen_error_codes.dart；输入：sdk/error-codes.json（version 1）+ RC 10.13.1 名表。
// 修改流程：改 sdk/error-codes.json → 在 sdk/flutter 下 `dart run scripts/gen_error_codes.dart`。
//
// 码 → 枚举按 name 对齐，不按下标：json 里的码按其 name 取同名枚举值，json 没有的码位按 RC 下标填。
// 28/29 与 RC 下标错位是有意的（主代理裁定）：e.code 仍是我方数字，getErrorCode 得到正确语义。
//   28: 我方 customerInfoError（RC 下标 28 为 productDiscountMissingSubscriptionGroupIdentifierError）
//   29: 我方 systemInfoError（RC 下标 29 为 customerInfoError）
// ignore_for_file: lines_longer_than_80_chars

/// 错误码枚举：RC `PurchasesErrorCode` 43 值原序（0–42）+ 我方专有码按码位升序追加（D4）。
///
/// 对照 RC：值集与顺序逐字同形。偏离：码位 → 枚举走 [purchasesErrorCodeByNumber] 按 name 显式查表，
/// 不按下标（900+ 不在下标范围内；我方 28/29 与 RC 下标错位）。
enum PurchasesErrorCode {
  unknownError, // RC 0
  purchaseCancelledError, // RC 1
  storeProblemError, // RC 2
  purchaseNotAllowedError, // RC 3
  purchaseInvalidError, // RC 4
  productNotAvailableForPurchaseError, // RC 5
  productAlreadyPurchasedError, // RC 6
  receiptAlreadyInUseError, // RC 7
  invalidReceiptError, // RC 8
  missingReceiptFileError, // RC 9
  networkError, // RC 10
  invalidCredentialsError, // RC 11
  unexpectedBackendResponseError, // RC 12
  receiptInUseByOtherSubscriberError, // RC 13
  invalidAppUserIdError, // RC 14
  operationAlreadyInProgressError, // RC 15
  unknownBackendError, // RC 16
  invalidAppleSubscriptionKeyError, // RC 17
  ineligibleError, // RC 18
  insufficientPermissionsError, // RC 19
  paymentPendingError, // RC 20
  invalidSubscriberAttributesError, // RC 21
  logOutWithAnonymousUserError, // RC 22
  configurationError, // RC 23
  unsupportedError, // RC 24
  emptySubscriberAttributesError, // RC 25
  productDiscountMissingIdentifierError, // RC 26
  unknownNonNativeError, // RC 27
  productDiscountMissingSubscriptionGroupIdentifierError, // RC 28
  customerInfoError, // RC 29
  systemInfoError, // RC 30
  beginRefundRequestError, // RC 31
  productRequestTimeout, // RC 32
  apiEndpointBlocked, // RC 33
  invalidPromotionalOfferError, // RC 34
  offlineConnectionError, // RC 35
  featureNotAvailableInCustomEntitlementsComputationMode, // RC 36
  signatureVerificationFailed, // RC 37
  featureNotSupportedWithStoreKit1, // RC 38
  invalidWebPurchaseToken, // RC 39
  purchaseBelongsToOtherUser, // RC 40
  expiredWebPurchaseToken, // RC 41
  testStoreSimulatedPurchaseError, // RC 42
  notImplementedError, // 900（我方专有）
  purchasePendingServerConfirmation, // 901（我方专有）
  purchaseRejectedByServer, // 902（我方专有）
}

/// 码位 → 枚举。json 里的码按 name 对齐，json 没有的 0–42 码位按 RC 下标。
///
/// 路径专用映射（裁定 6，不在本表体现）：原生 logOut 路径的我方 14 `invalidAppUserIdError`
/// 由原生插件改报 22（`logOutWithAnonymousUserError`，readable `LogOutWithAnonymousUserError`，
/// `details.revdogCode` 仍为 `invalidAppUserIdError`），只在 logOut 路径生效。
const Map<int, PurchasesErrorCode> purchasesErrorCodeByNumber = {
  0: PurchasesErrorCode.unknownError,
  1: PurchasesErrorCode.purchaseCancelledError,
  2: PurchasesErrorCode.storeProblemError,
  3: PurchasesErrorCode.purchaseNotAllowedError,
  4: PurchasesErrorCode.purchaseInvalidError,
  5: PurchasesErrorCode.productNotAvailableForPurchaseError,
  6: PurchasesErrorCode.productAlreadyPurchasedError,
  7: PurchasesErrorCode.receiptAlreadyInUseError,
  8: PurchasesErrorCode.invalidReceiptError,
  9: PurchasesErrorCode.missingReceiptFileError,
  10: PurchasesErrorCode.networkError,
  11: PurchasesErrorCode.invalidCredentialsError,
  12: PurchasesErrorCode.unexpectedBackendResponseError,
  13: PurchasesErrorCode.receiptInUseByOtherSubscriberError,
  14: PurchasesErrorCode.invalidAppUserIdError,
  15: PurchasesErrorCode.operationAlreadyInProgressError,
  16: PurchasesErrorCode.unknownBackendError,
  17: PurchasesErrorCode.invalidAppleSubscriptionKeyError,
  18: PurchasesErrorCode.ineligibleError,
  19: PurchasesErrorCode.insufficientPermissionsError,
  20: PurchasesErrorCode.paymentPendingError,
  21: PurchasesErrorCode.invalidSubscriberAttributesError,
  22: PurchasesErrorCode.logOutWithAnonymousUserError,
  23: PurchasesErrorCode.configurationError,
  24: PurchasesErrorCode.unsupportedError,
  25: PurchasesErrorCode.emptySubscriberAttributesError,
  26: PurchasesErrorCode.productDiscountMissingIdentifierError,
  27: PurchasesErrorCode.unknownNonNativeError,
  28: PurchasesErrorCode.customerInfoError,
  29: PurchasesErrorCode.systemInfoError,
  30: PurchasesErrorCode.systemInfoError,
  31: PurchasesErrorCode.beginRefundRequestError,
  32: PurchasesErrorCode.productRequestTimeout,
  33: PurchasesErrorCode.apiEndpointBlocked,
  34: PurchasesErrorCode.invalidPromotionalOfferError,
  35: PurchasesErrorCode.offlineConnectionError,
  36: PurchasesErrorCode.featureNotAvailableInCustomEntitlementsComputationMode,
  37: PurchasesErrorCode.signatureVerificationFailed,
  38: PurchasesErrorCode.featureNotSupportedWithStoreKit1,
  39: PurchasesErrorCode.invalidWebPurchaseToken,
  40: PurchasesErrorCode.purchaseBelongsToOtherUser,
  41: PurchasesErrorCode.expiredWebPurchaseToken,
  42: PurchasesErrorCode.testStoreSimulatedPurchaseError,
  900: PurchasesErrorCode.notImplementedError,
  901: PurchasesErrorCode.purchasePendingServerConfirmation,
  902: PurchasesErrorCode.purchaseRejectedByServer,
};

/// 码位 → `details.readableErrorCode` / `details.readable_error_code`（最终枚举名首字母大写）。
/// 原生插件两端按此表填值（D4：两端同值）；Dart 只用于测试与文档。
const Map<int, String> readableErrorCodeByNumber = {
  0: 'UnknownError',
  1: 'PurchaseCancelledError',
  2: 'StoreProblemError',
  3: 'PurchaseNotAllowedError',
  4: 'PurchaseInvalidError',
  5: 'ProductNotAvailableForPurchaseError',
  6: 'ProductAlreadyPurchasedError',
  7: 'ReceiptAlreadyInUseError',
  8: 'InvalidReceiptError',
  9: 'MissingReceiptFileError',
  10: 'NetworkError',
  11: 'InvalidCredentialsError',
  12: 'UnexpectedBackendResponseError',
  13: 'ReceiptInUseByOtherSubscriberError',
  14: 'InvalidAppUserIdError',
  15: 'OperationAlreadyInProgressError',
  16: 'UnknownBackendError',
  17: 'InvalidAppleSubscriptionKeyError',
  18: 'IneligibleError',
  19: 'InsufficientPermissionsError',
  20: 'PaymentPendingError',
  21: 'InvalidSubscriberAttributesError',
  22: 'LogOutWithAnonymousUserError',
  23: 'ConfigurationError',
  24: 'UnsupportedError',
  25: 'EmptySubscriberAttributesError',
  26: 'ProductDiscountMissingIdentifierError',
  27: 'UnknownNonNativeError',
  28: 'CustomerInfoError',
  29: 'SystemInfoError',
  30: 'SystemInfoError',
  31: 'BeginRefundRequestError',
  32: 'ProductRequestTimeout',
  33: 'ApiEndpointBlocked',
  34: 'InvalidPromotionalOfferError',
  35: 'OfflineConnectionError',
  36: 'FeatureNotAvailableInCustomEntitlementsComputationMode',
  37: 'SignatureVerificationFailed',
  38: 'FeatureNotSupportedWithStoreKit1',
  39: 'InvalidWebPurchaseToken',
  40: 'PurchaseBelongsToOtherUser',
  41: 'ExpiredWebPurchaseToken',
  42: 'TestStoreSimulatedPurchaseError',
  900: 'NotImplementedError',
  901: 'PurchasePendingServerConfirmation',
  902: 'PurchaseRejectedByServer',
};
