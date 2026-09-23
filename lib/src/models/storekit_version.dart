/// StoreKit 版本。对照 RC：值集与顺序逐字照 RC `StoreKitVersion`。
///
/// 我方原生只用 StoreKit 2（iOS 16+）：`configure` 时 `storeKit1` → 抛码 23；
/// `storeKit2` 与 `defaultVersion`（RC 语义「由 SDK 选最合适的」，iOS 16+ 即 StoreKit 2）放行。
/// 偏离：RC 另有扩展 `StoreKitVersionExtension.name`（发 `STOREKIT_2` 等通道值），我方不下发该字段，未声明。
enum StoreKitVersion {
  /// 始终用 StoreKit 1（我方不支持）。
  storeKit1,

  /// 始终用 StoreKit 2。
  storeKit2,

  /// 由 SDK 选择（我方即 StoreKit 2）。
  defaultVersion,
}
