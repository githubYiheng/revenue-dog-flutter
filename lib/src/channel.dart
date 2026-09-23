import 'package:flutter/services.dart';

/// Dart ↔ 原生插件的唯一通道（设计 §2「通道」）。
///
/// 对照 RC：一条 `MethodChannel` + `StandardMethodCodec`，通道名 = 包名（RC 为 `purchases_flutter`），
/// 双向复用：Dart → 原生 `invokeMethod`，原生 → Dart 反向 `invokeMethod`（事件）。不用 Pigeon。
const MethodChannel revenueDogMethodChannel = MethodChannel('revenue_dog');

/// Dart → 原生方法名（设计 §5 方法表；M1 用到的部分）。名字即契约，原生插件逐字匹配。
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
}

/// 原生 → Dart 事件名（设计 §5.7）。对照 RC：事件名逐字沿用。
abstract final class ChannelEvents {
  static const customerInfoUpdated = 'Purchases-CustomerInfoUpdated';
  static const logHandlerEvent = 'Purchases-LogHandlerEvent';
}
