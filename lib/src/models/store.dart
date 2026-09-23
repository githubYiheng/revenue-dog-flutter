/// 商店。对照 RC：值集与顺序逐字照 RC 10.13.1 `Store`（12 值）。
///
/// 通道值为我方小写枚举原样（`app_store`、`play_store`、`promotional`…，设计 §5.2），
/// 未知值（含我方 `roku`、`unknown`）→ [Store.unknownStore]。
enum Store {
  /// App Store。
  appStore,

  /// Mac App Store。
  macAppStore,

  /// Google Play。
  playStore,

  /// Stripe。
  stripe,

  /// 促销授予。
  promotional,

  /// 未知商店。
  unknownStore,

  /// Amazon Appstore（我方不支持，仅为 RC 值集保留）。
  amazon,

  /// RC Billing（我方不支持，仅为 RC 值集保留）。
  rcBilling,

  /// Paddle。
  paddle,

  /// RC Test Store（我方不支持，仅为 RC 值集保留）。
  testStore,

  /// 外部商店。
  externalStore,

  /// Galaxy Store（我方不支持，仅为 RC 值集保留）。
  galaxy,
}

/// 通道值 → [Store]（不导出）。未列出的值（含我方 `roku` / `unknown`）→ [Store.unknownStore]。
const Map<String, Store> storeByWire = {
  'app_store': Store.appStore,
  'mac_app_store': Store.macAppStore,
  'play_store': Store.playStore,
  'stripe': Store.stripe,
  'promotional': Store.promotional,
  'amazon': Store.amazon,
  'rc_billing': Store.rcBilling,
  'paddle': Store.paddle,
  'test_store': Store.testStore,
  'external': Store.externalStore,
  'galaxy': Store.galaxy,
};
