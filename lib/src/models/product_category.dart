/// 商品类别。对照 RC：值集与顺序逐字照 RC 10.13.1 `ProductCategory`。通道值 `subscription|non_subscription`。
///
/// 偏离 RC：同文件里 RC 已弃用的 `PurchaseType`（`inapp` / `subs`）不声明（旧购买 API 不做，D5）。
enum ProductCategory {
  /// 非订阅（消耗型 / 非消耗型）。
  nonSubscription,

  /// 订阅。
  subscription,
}

/// 通道值 → [ProductCategory]（不导出）。未知值 → `null`（照 RC `productCategoryFromJson`）。
const Map<String, ProductCategory> productCategoryByWire = {
  'non_subscription': ProductCategory.nonSubscription,
  'subscription': ProductCategory.subscription,
};
