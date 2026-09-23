import 'entitlement_verification_mode.dart';
import 'purchases_completed_by.dart';
import 'store.dart';
import 'storekit_version.dart';

/// `Purchases.configure` 的配置。
///
/// 对照 RC：字段集 = RC 10.13.1 `PurchasesConfiguration` 全量（名字、类型、默认值逐字照 RC），
/// 另加我方扩展 [waitsForLogInBeforeSync]、[baseUrl]（设计 §1 #1、裁定 9）。
///
/// 各字段在我方的去向（设计 §1 #1）：
/// - 直传原生：[apiKey]、[appUserID]、[diagnosticsEnabled]、[purchasesAreCompletedBy]、
///   [shouldShowInAppMessagesAutomatically]、[pendingTransactionsForPrepaidPlansEnabled]、
///   [userDefaultsSuiteName]、[waitsForLogInBeforeSync]、[baseUrl]；本平台不适用的由原生插件忽略并记诊断。
/// - 只支持单一取值、其它取值 `configure` 抛码 23：[storeKitVersion]（`storeKit1` 不支持）、
///   [entitlementVerificationMode]（仅 `disabled`）、[store]（`Store.amazon` 不支持）。
/// - 声明但不下发（偏离，待主代理裁定是否下发）：[preferredUILocaleOverride]、
///   [automaticDeviceIdentifierCollectionEnabled]。
///
/// RC 另有 `AmazonConfiguration` 子类（`store = Store.amazon`），我方不支持 Amazon，未声明。
class PurchasesConfiguration {
  /// RevenueDog 公钥（每个 app 一把）。
  final String apiKey;

  PurchasesConfiguration(this.apiKey);

  /// 覆盖设备语言（RC 用于付费墙 UI）。我方无付费墙：声明但不下发。
  String? preferredUILocaleOverride;

  /// 可选的 App User ID；不设则原生生成匿名 ID。
  String? appUserID;

  /// 谁来完成购买；默认（null）= SDK 完成。通道值 `revenue_dog` | `my_app`。
  PurchasesAreCompletedBy? purchasesAreCompletedBy;

  /// iOS-only：偏好存储的 UserDefaults suite。Android 忽略（原生插件记诊断）。
  String? userDefaultsSuiteName;

  /// iOS-only：StoreKit 版本。我方只用 StoreKit 2：`storeKit1` → `configure` 抛码 23。
  StoreKitVersion? storeKitVersion;

  /// 是否自动展示商店的应用内消息（计费问题等）。默认 true。
  bool shouldShowInAppMessagesAutomatically = true;

  /// RC 用于选 Amazon。我方不支持 Amazon：设为 `Store.amazon` → `configure` 抛码 23；其它值无效果（同 RC）。
  Store? store;

  /// 权益验证模式。我方无 Trusted Entitlements：非 `disabled` → `configure` 抛码 23。
  EntitlementVerificationMode entitlementVerificationMode =
      EntitlementVerificationMode.disabled;

  /// Android-only：允许预付费套餐的待定交易。默认 false。
  bool pendingTransactionsForPrepaidPlansEnabled = false;

  /// RC 用于归因网络的设备标识采集。我方不做归因网络：声明但不下发。默认 true（同 RC）。
  bool automaticDeviceIdentifierCollectionEnabled = true;

  /// 是否上报 SDK 诊断。默认 false（同 RC）。
  bool diagnosticsEnabled = false;

  /// 我方扩展，**iOS-only**：logIn 之前是否暂缓同步购买（ADR 0046–0048 身份门控）。默认 false。
  /// Android 静默忽略并记诊断 `hybrid_option_ignored`。
  bool waitsForLogInBeforeSync = false;

  /// 我方扩展：覆盖后端地址，**只给测试 / staging 构建用**，商店构建不设（裁定 9）。
  String? baseUrl;
}
