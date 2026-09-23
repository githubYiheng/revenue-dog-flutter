import 'storekit_version.dart';

/// 谁来完成（finish / acknowledge）购买。对照 RC：值集与顺序照 RC `PurchasesAreCompletedByType`。
///
/// 通道值：`revenue_dog` | `my_app`（设计 §5 `setupPurchases` 参数）。
/// 偏离：RC 的 `revenueCat` 值名保留（源码兼容），通道上发 `revenue_dog`；
/// RC 另有扩展 `PurchasesAreCompletedByTypeExtension.name`（发 `REVENUECAT` / `MY_APP`），我方未声明。
enum PurchasesAreCompletedByType {
  /// 宿主自己完成购买。
  myApp,

  /// SDK 完成购买（默认）。
  revenueCat,
}

/// 购买完成方（RC 的 sealed 形态，照 RC 为 abstract class + 两个子类）。
abstract class PurchasesAreCompletedBy {
  const PurchasesAreCompletedBy();
}

/// SDK 完成购买（默认）。对照 RC：类名逐字保留，语义 = RevenueDog 原生完成。
class PurchasesAreCompletedByRevenueCat extends PurchasesAreCompletedBy {
  const PurchasesAreCompletedByRevenueCat();
}

/// 宿主自己完成购买。对照 RC：构造签名逐字照 RC（`storeKitVersion` 必填）。
///
/// `storeKitVersion` 同样受 StoreKit 2 限制：`storeKit1` → `configure` 抛码 23。
class PurchasesAreCompletedByMyApp extends PurchasesAreCompletedBy {
  final StoreKitVersion storeKitVersion;

  PurchasesAreCompletedByMyApp({
    required this.storeKitVersion,
  });
}
