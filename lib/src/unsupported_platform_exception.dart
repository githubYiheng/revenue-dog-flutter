/// 在 iOS / Android 之外的平台（Web、macOS、Windows、Linux…）调用任何 [Purchases] 方法时抛出（D13）。
///
/// 对照 RC：类名与形状照 RC `UnsupportedPlatformException`（`implements Exception`，无字段）。
/// 偏离：RC 只在少数 iOS-only / Android-only 方法上抛；我方只支持 iOS / Android，所以全部公开方法都守卫。
class UnsupportedPlatformException implements Exception {}
