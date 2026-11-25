import 'package:flutter/services.dart';

/// Dart ↔ 原生插件的唯一通道（设计 §2「通道」）。
///
/// 对照 RC：一条 `MethodChannel` + `StandardMethodCodec`，通道名 = 包名（RC 为 `purchases_flutter`），
/// 双向复用：Dart → 原生 `invokeMethod`，原生 → Dart 反向 `invokeMethod`（事件）。不用 Pigeon。
const MethodChannel revenueDogMethodChannel = MethodChannel('revenue_dog');

/// Dart → 原生方法名（设计 §5 方法表，M1 + M2 共 17 个，rc.4 加 1 个）。名字即契约，原生插件逐字匹配。
abstract final class ChannelMethods {
  static const setupPurchases = 'setupPurchases';
  static const getConfiguredParams = 'getConfiguredParams';
  static const attachCustomerInfoStream = 'attachCustomerInfoStream';
  static const isConfigured = 'isConfigured';
  static const getAppUserID = 'getAppUserID';
  static const isAnonymous = 'isAnonymous';
  static const setLogLevel = 'setLogLevel';
  static const setLogHandler = 'setLogHandler';
  static const logIn = 'logIn';
  static const logOut = 'logOut';
  static const getCustomerInfo = 'getCustomerInfo';
  static const enableAdServicesAttributionTokenCollection =
      'enableAdServicesAttributionTokenCollection';

  // M2：目录与购买（设计 §5 方法表、§3）。
  /// 无参 → Offerings map（§5.3）。
  static const getOfferings = 'getOfferings';

  /// `{offeringIdentifier, packageIdentifier}` → PurchaseResult map（§5.5）。
  static const purchasePackage = 'purchasePackage';

  /// 无参 → CustomerInfo map。
  static const restorePurchases = 'restorePurchases';

  /// 无参 → CustomerInfo map（Dart 丢弃返回值）。
  static const syncPurchases = 'syncPurchases';

  /// `{productIdentifiers: List<String>}` → `{productId: {status, description}}`（§5.5）。
  static const checkTrialOrIntroductoryPriceEligibility = 'checkTrialOrIntroductoryPriceEligibility';

  // rc.4：保留属性 setter（设计 §5.8，ADR 0245）。
  /// `{key: <原生保留键，如 $idfa>, value: String? | bool?}` → null。十个门面 setter 共用这一条；
  /// 键表 = `test/fixtures/wire/reserved-attributes.json`（三方对账），原生按键分派到同名原生 setter。
  static const setReservedAttribute = 'setReservedAttribute';
}

/// 原生 → Dart 事件名（设计 §5.7）。对照 RC：事件名逐字沿用。
abstract final class ChannelEvents {
  static const customerInfoUpdated = 'Purchases-CustomerInfoUpdated';
  static const logHandlerEvent = 'Purchases-LogHandlerEvent';
}
