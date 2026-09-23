import 'package.dart';

/// `Purchases.purchase` 的参数。对照 RC：类名、`PurchaseParams.package(Package)` 构造、`package` 字段逐字照 RC 10.13.1。
///
/// 偏离 RC（D5、设计 §1 #21）：v1 只提供 `.package` 构造；RC 的 `.storeProduct` / `.subscriptionOption` 构造、
/// 升降级（`productChangeInfo` / `googleProductChangeInfo`）、`googleIsPersonalizedPrice`、`promotionalOffer`、
/// `winBackOffer`、`customerEmail` 及对应字段均不声明 —— 宿主用到即编译报错（fail-loud），不静默忽略。
class PurchaseParams {
  /// 要购买的 package。
  final Package? package;

  const PurchaseParams._(this.package);

  /// 购买一个 package。
  const PurchaseParams.package(Package package) : this._(package);
}
