import 'models/customer_info.dart';
import 'models/log_level.dart';

/// 监听者类型。对照 RC：签名逐字照 RC `CustomerInfoUpdateListener`。
typedef CustomerInfoUpdateListener = void Function(CustomerInfo customerInfo);

/// 日志回调类型。对照 RC：签名逐字照 RC `LogHandler`。
typedef LogHandler = void Function(LogLevel logLevel, String message);

/// `Purchases` 的 Dart 侧内存态（设计 §4：Flutter 层不持久化任何东西）。
///
/// 独立成不导出的库，便于测试模拟热重启（[reset] = Dart 静态态清零，插件记录与原生单例仍在）。
abstract final class PurchasesState {
  /// 监听者集合（RC 同款 `Set`）。
  static final Set<CustomerInfoUpdateListener> customerInfoUpdateListeners = {};

  /// 最近一次收到的 CustomerInfo，新加监听者立即回放（照 RC）。
  static CustomerInfo? lastReceivedCustomerInfo;

  /// 宿主设置的日志回调。
  static LogHandler? logHandler;

  /// R4：最近一次 `setLogLevel` 的值，`configure` 时写进 `setupPurchases` 的 `logLevel`。
  static LogLevel? lastLogLevel;

  /// 清零全部 Dart 静态态（模拟热重启）。
  static void reset() {
    customerInfoUpdateListeners.clear();
    lastReceivedCustomerInfo = null;
    logHandler = null;
    lastLogLevel = null;
  }
}
