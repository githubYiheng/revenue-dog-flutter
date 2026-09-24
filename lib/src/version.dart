/// 插件版本，随 `setupPurchases` 的 `platformFlavorVersion` 下发，原生写进
/// `X-Platform-Flavor-Version` 请求头（设计 §5 方法表、D12）。
///
/// 由 pubspec 生成，脚本 M3 定稿（暂名 `scripts/sdk-flutter-pin.sh`，裁定 4）；
/// 在此之前手动维护，`test/version_test.dart` 校验与 pubspec `version` 一致。
const String revenueDogFlutterVersion = '0.1.0-rc.2';
