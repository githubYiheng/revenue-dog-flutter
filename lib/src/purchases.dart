import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'channel.dart';
import 'errors.dart';
import 'generated/error_codes.dart';
import 'models/customer_info.dart';
import 'models/entitlement_verification_mode.dart';
import 'models/log_in_result.dart';
import 'models/log_level.dart';
import 'models/purchases_completed_by.dart';
import 'models/purchases_configuration.dart';
import 'models/store.dart';
import 'models/storekit_version.dart';
import 'purchases_state.dart';
import 'unsupported_platform_exception.dart';
import 'version.dart';
import 'wire.dart';

/// RevenueDog 门面。对照 RC：`class Purchases` 全静态，成员名 / 签名逐字照 RC `purchases_flutter`。
///
/// M1 提供：configure / setLogLevel / isConfigured / logIn / logOut / appUserID / isAnonymous /
/// getCustomerInfo / enableAdServicesAttributionTokenCollection / add·removeCustomerInfoUpdateListener /
/// setLogHandler。M2 追加 offerings / purchase / restore / sync / eligibility。
///
/// 全部方法先做平台守卫（D13）：Web 或 iOS / Android 以外的平台抛 [UnsupportedPlatformException]
/// （`removeCustomerInfoUpdateListener` 是纯 Dart 集合操作，不守卫）。
/// 原生错误以 `PlatformException(code: '<十进制码>')` 原样抛出；返回值解码失败抛码 12（设计 §5 总则）。
class Purchases {
  static final MethodChannel _channel = revenueDogMethodChannel
    ..setMethodCallHandler(_handleNativeCall);

  static void _ensureSupportedPlatform() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedPlatformException();
    }
  }

  static Future<Object?> _invoke(String method, [Map<String, Object?>? arguments]) {
    _ensureSupportedPlatform();
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  static void _log(LogLevel level, String message) {
    final handler = PurchasesState.logHandler;
    if (handler != null) {
      handler(level, message);
    } else {
      debugPrint('[RevenueDog] ${level.name.toUpperCase()}: $message');
    }
  }

  // ---------------------------------------------------------------------------
  // 原生 → Dart 事件（设计 §5.7）
  // ---------------------------------------------------------------------------

  static Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case ChannelEvents.customerInfoUpdated:
        final CustomerInfo customerInfo;
        try {
          customerInfo = decodeCustomerInfo(WireMap.fromChannel(call.arguments));
        } on PlatformException catch (e) {
          _log(LogLevel.error, 'failed to decode ${call.method}: ${e.details}');
          rethrow;
        }
        PurchasesState.lastReceivedCustomerInfo = customerInfo;
        for (final listener in List.of(PurchasesState.customerInfoUpdateListeners)) {
          listener(customerInfo);
        }
      case ChannelEvents.logHandlerEvent:
        final args = WireMap.fromChannel(call.arguments);
        final levelName = args.optionalString('logLevel');
        // 未知级别落 info（照 RC）。
        final level = LogLevel.values.firstWhere(
          (e) => e.name == levelName,
          orElse: () => LogLevel.info,
        );
        PurchasesState.logHandler?.call(level, args.requireString('message'));
    }
  }

  // ---------------------------------------------------------------------------
  // 配置
  // ---------------------------------------------------------------------------

  /// 配置 SDK。同一进程只配置一次，参数固定；换用户用 [logIn] / [logOut]。
  ///
  /// 流程（设计 §4 R3）：
  /// 1. 平台守卫（D13）与配置校验（不支持的取值抛码 23，不下发）；
  /// 2. `getConfiguredParams` 取插件进程级记录：未配置 → `setupPurchases`；
  ///    已配置且 `(apiKey, appUserID)` 与首次相同 → 不下发，`attachCustomerInfoStream` 为本引擎挂订阅并推当前值，
  ///    打 warn（热重启 / 多引擎的正常路径）；不同 → 抛码 23。
  /// 3. 成功后原生经 `Purchases-CustomerInfoUpdated` 推一次当前值（D14），Dart 不主动拉。
  ///
  /// 偏离 RC：RC 重复 configure 会替换原生实例；我方异参直接报错（R3，fail-loud + 两端一致）。
  static Future<void> configure(PurchasesConfiguration purchasesConfiguration) async {
    _ensureSupportedPlatform();
    final completedBy = _validateConfiguration(purchasesConfiguration);

    final recordRaw = await _invoke(ChannelMethods.getConfiguredParams);
    final record = WireMap.fromChannel(recordRaw);
    if (!record.requireBool('isConfigured')) {
      await _invoke(ChannelMethods.setupPurchases, {
        'apiKey': purchasesConfiguration.apiKey,
        'appUserID': purchasesConfiguration.appUserID,
        'diagnosticsEnabled': purchasesConfiguration.diagnosticsEnabled,
        'logLevel': PurchasesState.lastLogLevel?.name,
        'waitsForLogInBeforeSync': purchasesConfiguration.waitsForLogInBeforeSync,
        'baseUrl': purchasesConfiguration.baseUrl,
        'platformFlavorVersion': revenueDogFlutterVersion,
        'purchasesAreCompletedBy': completedBy,
        'shouldShowInAppMessagesAutomatically':
            purchasesConfiguration.shouldShowInAppMessagesAutomatically,
        'pendingTransactionsForPrepaidPlansEnabled':
            purchasesConfiguration.pendingTransactionsForPrepaidPlansEnabled,
        'userDefaultsSuiteName': purchasesConfiguration.userDefaultsSuiteName,
      });
      return;
    }

    final recordedApiKey = record.optionalString('apiKey');
    final recordedAppUserID = record.optionalString('appUserID');
    if (recordedApiKey == purchasesConfiguration.apiKey &&
        recordedAppUserID == purchasesConfiguration.appUserID) {
      _log(
        LogLevel.warn,
        'Purchases is already configured with the same apiKey / appUserID; '
        'reusing the existing instance and re-attaching the CustomerInfo stream.',
      );
      await _invoke(ChannelMethods.attachCustomerInfoStream, {'duplicateConfigure': true});
      return;
    }

    throw buildPurchasesPlatformException(
      PurchasesErrorCode.configurationError,
      message: 'Purchases is already configured with a different apiKey / appUserID. '
          'Configure only once per process; use logIn / logOut to switch users.',
      underlyingErrorMessage: 'configure called again with different parameters',
    );
  }

  /// 校验配置（设计 §1 #1），返回通道值 `purchasesAreCompletedBy`（`revenue_dog` | `my_app`）。
  static String _validateConfiguration(PurchasesConfiguration c) {
    Never reject(String reason) => throw buildPurchasesPlatformException(
          PurchasesErrorCode.configurationError,
          underlyingErrorMessage: reason,
        );

    if (c.storeKitVersion == StoreKitVersion.storeKit1) {
      reject('storeKitVersion storeKit1 is not supported; RevenueDog uses StoreKit 2 only');
    }
    if (c.entitlementVerificationMode != EntitlementVerificationMode.disabled) {
      reject('entitlementVerificationMode ${c.entitlementVerificationMode.name} is not supported; '
          'only disabled is supported');
    }
    if (c.store == Store.amazon) {
      reject('Store.amazon is not supported');
    }
    final completedBy = c.purchasesAreCompletedBy;
    if (completedBy is PurchasesAreCompletedByMyApp) {
      if (completedBy.storeKitVersion == StoreKitVersion.storeKit1) {
        reject('PurchasesAreCompletedByMyApp(storeKitVersion: storeKit1) is not supported; '
            'RevenueDog uses StoreKit 2 only');
      }
      return 'my_app';
    }
    return 'revenue_dog';
  }

  /// 设置日志级别。可在 [configure] 之前调用：Dart 记住最近值并在 configure 时写进配置（R4）。
  ///
  /// 偏离 RC：RC 的 logLevel 纯静态；我方原生 configure 会用配置覆盖日志级别，故由插件带入（R4）。
  static Future<void> setLogLevel(LogLevel level) async {
    _ensureSupportedPlatform();
    PurchasesState.lastLogLevel = level;
    await _invoke(ChannelMethods.setLogLevel, {'level': level.name});
  }

  /// 设置日志回调；之后原生经 `Purchases-LogHandlerEvent` 推送日志。
  static Future<void> setLogHandler(LogHandler logHandler) async {
    _ensureSupportedPlatform();
    PurchasesState.logHandler = logHandler;
    await _invoke(ChannelMethods.setLogHandler);
  }

  /// SDK 是否已配置。
  static Future<bool> get isConfigured async =>
      _expect<bool>(await _invoke(ChannelMethods.isConfigured), ChannelMethods.isConfigured);

  // ---------------------------------------------------------------------------
  // 身份
  // ---------------------------------------------------------------------------

  /// 以 [appUserID] 登录。结果含 `created`（后端首次创建）与登录后的 [CustomerInfo]。
  static Future<LogInResult> logIn(String appUserID) async {
    final result = await _invoke(ChannelMethods.logIn, {'appUserID': appUserID});
    return decodeLogInResult(WireMap.fromChannel(result));
  }

  /// 登出，切回新的匿名用户。当前已是匿名用户时抛码 22（`logOutWithAnonymousUserError`，同 RC）。
  static Future<CustomerInfo> logOut() async =>
      decodeCustomerInfo(WireMap.fromChannel(await _invoke(ChannelMethods.logOut)));

  /// 当前 App User ID（每次现取，Dart 不持有身份）。
  static Future<String> get appUserID async =>
      _expect<String>(await _invoke(ChannelMethods.getAppUserID), ChannelMethods.getAppUserID);

  /// 当前用户是否为匿名用户。
  static Future<bool> get isAnonymous async =>
      _expect<bool>(await _invoke(ChannelMethods.isAnonymous), ChannelMethods.isAnonymous);

  // ---------------------------------------------------------------------------
  // CustomerInfo
  // ---------------------------------------------------------------------------

  /// 取当前 CustomerInfo（原生缓存优先，不暴露 fetchPolicy，同 RC）。
  static Future<CustomerInfo> getCustomerInfo() async =>
      decodeCustomerInfo(WireMap.fromChannel(await _invoke(ChannelMethods.getCustomerInfo)));

  /// 添加 CustomerInfo 更新监听。已有最近值时立即回调一次（照 RC）。
  static void addCustomerInfoUpdateListener(
    CustomerInfoUpdateListener customerInfoUpdateListener,
  ) {
    _ensureSupportedPlatform();
    // 首次访问通道时注册事件处理器（与 RC 静态初始化同效）。
    _channel;
    PurchasesState.customerInfoUpdateListeners.add(customerInfoUpdateListener);
    final last = PurchasesState.lastReceivedCustomerInfo;
    if (last != null) customerInfoUpdateListener(last);
  }

  /// 移除 CustomerInfo 更新监听。
  static void removeCustomerInfoUpdateListener(
    CustomerInfoUpdateListener listenerToRemove,
  ) =>
      PurchasesState.customerInfoUpdateListeners.remove(listenerToRemove);

  // ---------------------------------------------------------------------------
  // 归因
  // ---------------------------------------------------------------------------

  /// iOS：开启 AdServices 归因 token 采集。Android 静默成功（宿主不判平台就调，08 §8.3 #15）。
  static Future<void> enableAdServicesAttributionTokenCollection() async {
    await _invoke(ChannelMethods.enableAdServicesAttributionTokenCollection);
  }

  static T _expect<T>(Object? value, String wireKey) {
    if (value is! T) throwWireError(wireKey, 'expected $T, got ${value.runtimeType}');
    return value;
  }
}
